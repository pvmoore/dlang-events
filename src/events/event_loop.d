module events.event_loop;
/**
 * Simple message loop where each message type has a unique
 * bit mask. eg. message type 1 can use bit mask 1<<0 and
 * message type 4 can use bit 1<<4 for example. This means
 * the max number of message types is currently 64.
 *
 * Subscribe:
 *      getEvents().subscribe(mask, delegate);
 *
 * Unsubscribe:
 *      getEvents().unsubscribe(mask, delegate);
 *
 * Fire a message:
 *      getEvents().fire(message);
 */
import events.all;

__gshared EventLoop msgLoop;

alias MessageDelegate = void delegate(EventMsg);

void initEvents(uint queueSize) {
    log("Initialising events");
    msgLoop = new EventLoop(queueSize);
}
EventLoop getEvents() {
    assert(msgLoop !is null, "Call initEvents() before getEvents()");
    return msgLoop;
}

final class EventLoop {
private:
    Semaphore semaphore;
    IQueue!EventMsg queue;
    Subscriber[] subscribers;
    Mutex subscriberMutex;
    Thread[] threads;
    bool running = true;
public:
    this(uint queueSize) {
        this.log("Creating with queueSize %s", queueSize);
        this.semaphore       = new Semaphore();
        this.queue           = makeMPMCQueue!EventMsg(queueSize);
        this.subscriberMutex = new Mutex;

        startMessageThreads(1);
    }
    ~this() {
        running.atomicSet(false);
        foreach(i; 0..threads.length) {
            semaphore.notify();
        }
    }
    override string toString() {
        return "[EventLoop #threads=%s]".format(getNumThreads());
    }
    uint getNumThreads() {
        return cast(uint)threads.length;
    }
    Tuple!(string,ulong,ulong,uint)[] getSubscriberStats() {
        subscriberMutex.lock();
        scope(exit) subscriberMutex.unlock();

        return subscribers[]
            .map!(it=>tuple(
                it.name,
                it.msgMask,
                cast(ulong)it.watch.peek().total!"nsecs",
                it.count)
                )
            .array;
    }
    void shutdown() {
        running = false;
        for(auto i=0; i<threads.length; i++) {
            semaphore.notify();
        }
    }
    void addThreads(int num) {
        startMessageThreads(num);
    }
    void subscribe(string name, ulong mask, MessageDelegate d) {
        this.log("subscribe %s 0x%x", name, mask);

        subscriberMutex.lock();
        scope(exit) subscriberMutex.unlock();

        // COW
        auto temp = subscribers.dup;
        temp ~= new DelegateSubscriber(name, mask, d);
        this.subscribers = temp;
    }
    void subscribe(string name, ulong mask, IQueue!EventMsg queue, Semaphore sem=null) {
        this.log("subscribe %s 0x%x", name, mask);

        subscriberMutex.lock();
        scope(exit) subscriberMutex.unlock();

        // COW
        auto temp = subscribers.dup;
        temp ~= new QueueSubscriber(name, mask, queue, sem);
        this.subscribers = temp;
    }
    void unsubscribe(string name, ulong mask=ulong.max) {
        this.log("unsubscribe %s 0x%x", name, mask);

        subscriberMutex.lock();
        scope(exit) subscriberMutex.unlock();

        auto temp = subscribers.dup;

        for(auto i=0; i<temp.length; i++) {
            if(temp[i].name==name) {
                temp[i].msgMask &= ~mask;

                if(temp[i].msgMask==0) {
                    temp.removeAt(i);
                }
                // COW
                this.subscribers = temp;
                return;
            }
        }
    }
    void fire(EventMsg m) {
        queue.push(m);
        semaphore.notify();
    }
    void fire(T)(ulong id, T value) {
        fire(EventMsg(id, value));
    }
private:
    void startMessageThreads(int numThreads) {
        this.log("Starting %s message threads (%s total message threads)", numThreads, threads.length+1);
        for(auto i=0; i<numThreads; i++) {
            auto t = new Thread(&loop);
            t.isDaemon = true;
            t.name = "msg-%s".format(threads.length);
            threads ~= t;
            t.start();
        }
    }
    void loop() {
        EventMsg[4] sink;

        while(true) {
            try{
                // Consume a notification/wait
                semaphore.wait();

                // Take the next 4 items off the queue if possible
                while(running.atomicIsTrue()) {
                    auto count = queue.drain(sink);
                    if(count==0) break;

                    foreach(i; 0..count) {
                        auto msg = sink[i];
                        handleMessage(msg);
                    }
                }

                // No more work

            }catch(Error e) {
                this.log("%s exception: %s", Thread.getThis().name, e.toString);
            }
        }
    }
    void handleMessage(EventMsg msg) {
        auto id   = msg.id;
        auto subs = this.subscribers;

        foreach(s; subs) {
            if(s.msgMask & id) {
                s.count++;
                s.watch.start();
                auto ds = cast(DelegateSubscriber)s;
                if(ds) {
                    ds.call(msg);
                } else {
                    auto qs = cast(QueueSubscriber)s;
                    qs.queue.push(msg);
                    if(qs.semaphore) {
                        qs.semaphore.notify();
                    }
                }
                s.watch.stop();
            }
        }
    }
}

