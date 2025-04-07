
import std.stdio : writefln;
import std.format : format;
import core.thread;
import common.containers : IQueue, makeMPMCQueue; 
import events;

void main() {

    class MyClass {
        int a;
        this(int a) { this.a = a; }
        override string toString() {
            return "a=%s".format(a);
        }
    }

    auto intPtr = [cast(int)7,8,9].ptr;
    auto payload = new MyClass(57);

    initEvents(1024);

    getEvents().addThreads(1);

    auto queue = makeMPMCQueue!EventMsg(64);


    getEvents().subscribe("Barry", 2, (EventMsg m)=> writefln("I am Barry %s", m.get!double));
    getEvents().subscribe("Bill", 1, (EventMsg m)=> writefln("hello %s", m.get!MyClass));
    getEvents().subscribe("Bert", 1, (EventMsg m)=> getEvents().fire(EventMsg(2, 99.9f)));
    getEvents().subscribe("Nasty", 1, (EventMsg m)=>doSomething(m));
    getEvents().subscribe("Int fan", 4, (EventMsg m)=> writefln("int ptr: %s", m.get!(int*)[0]));

    getEvents().subscribe("BodWithQueue", 1, queue);

    getEvents().unsubscribe("Nasty", 1);

    getEvents().fire(EventMsg(1, payload));
    getEvents().fire(EventMsg(1, payload));
    getEvents().fire(EventMsg(1, payload));
    getEvents().fire(EventMsg(4, intPtr));

    Thread.sleep(dur!"msecs"(2000));

    writefln("%s", getEvents().toString);

    writefln("queue has %s messages", queue.length);
    auto msgs = new EventMsg[10];
    writefln("%s", queue.drain(msgs));

    writefln("Current subscribers:");
    foreach(t; getEvents().getSubscriberStats) {
        writefln("%s :  mask=%x time=%s millis msgs=%s", t[0], t[1], t[2]/1000000.0, t[3]);
    }

    getEvents().shutdown();
}

void doSomething(EventMsg m) {
    throw new Error("Oh dear");
}
