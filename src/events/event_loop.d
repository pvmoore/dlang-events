module events.event_loop;
/**
 * Simple message loop where each message type has a unique
 * bit mask. eg. message type 1 can use bit mask 1<<0 and
 * message type 4 can use bit 1<<4 for example. This means
 * the max number of message types is currently 64.
 *
 * Subscribe:
 *      messages().subscribe(mask, delegate);
 *
 * Unsubscribe:
 *      messages().unsubscribe(mask, delegate);
 *
 * Fire a message:
 *      messages().fire(message);
 */
import events.all;

__gshared EventLoop msgLoop;
//========================================================

alias MessageDelegate = void delegate(EventMsg);

void initEvents(uint queueSize) {
    msgLoop = new EventLoop(queueSize);
}
EventLoop getEvents() {
    assert(msgLoop !is null, "Call initEvents() before getEvents()");
    return msgLoop;
}

abstract class Subscriber {
    ulong msgMask;
    string name;
    StopWatch watch;
    uint count;
    this(string name, ulong mask) {
        this.name    = name;
        this.msgMask = mask;
    }
}
final class DelegateSubscriber : Subscriber {
    MessageDelegate call;
    this(string name, ulong mask, MessageDelegate m) {
        super(name,mask);
        this.call = m;
    }
}
final class QueueSubscriber : Subscriber {
    IQueue!EventMsg queue;
    Semaphore semaphore;
    this(string name, ulong mask, IQueue!EventMsg queue, Semaphore s) {
        super(name,mask);
        this.queue     = queue;
        this.semaphore = s;
    }
}

final class EventLoop {
private:
    Semaphore semaphore;
    IQueue!EventMsg queue;
    Array!Subscriber subscribers;
    Mutex subscriberMutex;
    Thread[] threads;
    bool running = true;
public:
    this(uint queueSize) {
        this.semaphore   = new Semaphore();
        this.queue       = makeMPMCQueue!EventMsg(queueSize);
        this.subscribers = new Array!Subscriber;
        this.subscriberMutex = new Mutex;
        this.threads.assumeSafeAppend();
        startMessageThreads(1);
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
    @Async
    void subscribe(string name, ulong mask, MessageDelegate d) {
        subscriberMutex.lock();
        scope(exit) subscriberMutex.unlock();

        subscribers.add(new DelegateSubscriber(name, mask, d));
    }
    @Async
    void subscribe(string name, ulong mask, IQueue!EventMsg queue, Semaphore sem=null) {
        subscriberMutex.lock();
        scope(exit) subscriberMutex.unlock();

        subscribers.add(new QueueSubscriber(name, mask, queue, sem));
    }
    @Async
    void unsubscribe(string name, ulong mask=ulong.max) {
        subscriberMutex.lock();
        scope(exit) subscriberMutex.unlock();

        for(auto i=0; i<subscribers.length; i++) {
            if(subscribers[i].name==name) {
                subscribers[i].msgMask &= ~mask;
                if(subscribers[i].msgMask==0) {
                    subscribers.removeAt(i);
                }
                return;
            }
        }
    }
    @Async
    void fire(EventMsg m) {
        queue.push(m);
        semaphore.notify();
    }
private:
    void startMessageThreads(int numThreads) {
        for(auto i=0; i<numThreads; i++) {
            auto t = new Thread(&loop);
            t.isDaemon = true;
            t.name = "msg-%s".format(threads.length);
            threads ~= t;
            t.start();
        }
    }
    Subscriber[] copySubscribers() {
        subscriberMutex.lock();
        scope(exit) subscriberMutex.unlock();

        return subscribers[].dup;
    }
    void loop() {
        while(true) {
            try{
                semaphore.wait();
                if(!running) break;

                // check the queue for work
                auto msg  = queue.pop();
                auto id   = msg.id;
                auto subs = copySubscribers();

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
            }catch(Error e) {
                log("Events: %s exception: %s", Thread.getThis().name, e.toString);
            }
        }
    }
}

