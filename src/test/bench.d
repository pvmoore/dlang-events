module test.bench;

import core.time              : dur;
import core.thread            : Thread;
import core.sync.semaphore    : Semaphore;

import std.stdio              : writefln;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.random             : uniform01;
import std.range              : iota, array;
import std.format             : format; 
import std.algorithm;

import common.containers : IQueue, makeSPSCQueue; 
import common.utils;
import events;

void runBenchmarks() {
    initEvents(1024);

    EventLoop events = getEvents();

    // We have a single thread event loop
    throwIf(events.getNumThreads() != 1);

    writefln("Benchmarking single threaded event loop");

    QueueSubscriber[] subscribers = iota(0, 10).array.map!(a => new QueueSubscriber()).array;

    // Everyone subscribes to event type 1
    foreach(s; subscribers) {
        events.subscribe(s.name, 1, s.queue, s.semaphore);
    }

    enum NUM_MESSAGES = 100;

    int[] payloads = iota(0, NUM_MESSAGES).map!(i => cast(int)(uniform01() * 100)).array;

    // Publish some messages
    foreach(p; payloads) {
        events.fire(EventMsg(1, p));
    }

    writefln("Shutting down");
    events.shutdownAndWait();
    writefln("Shutdown complete");
}

void queueSubscribers(uint numSubscribers) {
    
}

final class QueueSubscriber {
    string name;
    Semaphore semaphore;
    StopWatch watch;
    IQueue!EventMsg queue;

    static uint ids;

    this() {
        this.name = "S%s".format(ids++);
        this.semaphore = new Semaphore();
        this.watch = StopWatch(AutoStart.no);
        this.queue = makeSPSCQueue!EventMsg(1024);
    }
}
