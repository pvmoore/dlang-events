module test.test;

import core.time   : dur;
import core.thread : Thread;

import std.stdio  : writefln;
import std.format : format;

import common.containers : IQueue, makeSPSCQueue, makeMPMCQueue; 
import events;

import test.bench;

void main() {

    const BENCHMARK = false;

    if(BENCHMARK) {
        runBenchmarks();
    } else {
        test1();
        test2();
    }
}

void test1() {
    writefln("Basic tests");

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
    assert(getEvents().getNumThreads() == 1);

    getEvents().addThreads(1);
    assert(getEvents().getNumThreads() == 2);

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

    getEvents().shutdownAndWait();
    writefln("Basic tests done");
}

void test2() {
    writefln("Larger test");

    initEvents(1024*1024);
    assert(getEvents().getNumThreads() == 1);

    final class Thing {
        ulong value;
        this(ulong value) { this.value = value; }
    }

    enum THING_CREATED = 0b1;
    enum COUNT = 10_000;

    final class Consumer {
        this(string name) {
            enum mask = THING_CREATED;

            this.name = name;
            this.eventConsumer = new EventConsumer!16(name, mask, makeSPSCQueue!EventMsg(1024*1024));
            this.thread = new Thread(&this.run);
            this.thread.isDaemon(true);
            this.thread.start();
        }
        string name;
        EventConsumer!16 eventConsumer;
        Thread thread;
        uint numReceived;
        uint[ulong] receivedIds;
        bool[ulong] receivedValues;
        bool running = true;

        void run() {
            while(running) {
                uint count = eventConsumer.processMessages((m) {
                    numReceived++;
                    receivedIds[m.id]++;

                    Thing th = m.get!Thing;
                    receivedValues[cast(uint)th.value] = true;
                });

                // Sleep for a bit
                if(count == 0) {
                    Thread.sleep(dur!"msecs"(100));
                }
            }
            if(true || numReceived < COUNT) {
                //writefln("%s Missing some ids %s", name, receivedValues.length);
                foreach(i; 0..COUNT) {
                    auto ptr = i in receivedValues;
                    if(ptr is null) {
                        writefln("%s Missing id %s", name, i);
                    }
                }
            }
            writefln("%s numReceived = %s", name, numReceived);
            writefln("%s receivedIds = %s", name, receivedIds);
        }
    }

    auto c1 = new Consumer("c1");
    auto c2 = new Consumer("c2");

    auto eventLoop = getEvents();

    Thing[] things;

    foreach(i; 0..COUNT) {
        auto thing = new Thing(i);
        things ~= thing;
        eventLoop.fire(EventMsg(THING_CREATED, thing));
    }

    writefln("Waiting for 2 seconds");
    Thread.sleep(dur!"msecs"(2000));

    c1.running = false;
    c2.running = false;

    writefln("Waiting for 1 second");
    Thread.sleep(dur!"msecs"(1000));

    getEvents().shutdownAndWait();
    writefln("Larger test done");
}

void doSomething(EventMsg m) {
    throw new Error("Oh dear");
}
