module events.subscriber;

import events.all;

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
