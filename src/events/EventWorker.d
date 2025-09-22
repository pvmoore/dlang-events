module events.EventWorker;

import events.all;

import core.thread         : Thread;
import core.time           : dur;
import core.sync.semaphore : Semaphore;
import common.utils        : Atomic;
import logging             : FileLogger;
import common.containers   : MutexQueue;
import std.format          : format;
import std.string          : toLower;

/**
 * Common superclass for an event worker thread.
 *
 * Override the messageProcessor() method to process events into something that can be
 * used by the work() method.
 * Override the work() method to do the work.
 *
 * @param N: Process up to N events before calling work() on every loop
 */
final class EventWorker(uint N) {
public:
    this(string name, ulong eventMask, uint queueLength) {
        this.name = name;
        this.messages = new MutexQueue!EventMsg(queueLength);
        this.thread = new Thread(&run);
        this.thread.isDaemon(true);

        getEvents().subscribe(name, eventMask, messages);
    }
    void start() {
        throwIf(workDelegate is null, "workDelegate is not set");
        throwIf(messageProcessorDelegate is null, "messageProcessorDelegate is not set");

        if(isStarted.compareAndSet(false, true)) {
            thread.start();
        }
    }
    void shutdown(bool andWait) {
        if(shuttingDown.compareAndSet(false, true)) {
            if(andWait && isStarted.get()) {
                thread.join();
            }
            if(ownedLogger) {
                logger.close();
            }
        }
    }
    bool isShuttingDown() {
        return shuttingDown.get();
    }
    /** If true then we will consume all available events before doing any work. Default is false */
    void setGreedyConsumeEvents(bool greedy) {
        this.greedyConsumeEvents = greedy;
    }
    /** Set the number of times we can spin round without any work or events before we hibernate */
    void setIdleThreshold(uint limit, uint sleepTimeMs) {
        this.idleLimit = limit;
        this.idleSleepTimeMs = sleepTimeMs;
    }
    /** Set the logger to use.  If not set then a default logger will be created */
    void setLogger(FileLogger logger, string prefix = null) {
        this.logger = logger;
        this.logPrefix = prefix ? prefix ~ " " : "";
        this.ownedLogger = false;
    }
    /** Do some work.  Return false to indicate that there is no work to do at the moment */
    void setWorkDelegate(bool delegate() workDelegate) {
        this.workDelegate = workDelegate;
    }
    void setMessageProcessorDelegate(void delegate(EventMsg) messageProcessorDelegate) {
        this.messageProcessorDelegate = messageProcessorDelegate;
    }
protected:
    string name;
    EventWorker workerThread;
    IQueue!EventMsg messages;

    Thread thread;
    Atomic!bool shuttingDown = false; 
    Atomic!bool isStarted = false;
    FileLogger logger;
    string logPrefix;
    bool ownedLogger = false;
    uint idleLimit = 5;
    uint idleSleepTimeMs = 100;
    bool greedyConsumeEvents = false;

    bool delegate() workDelegate;
    void delegate(EventMsg) messageProcessorDelegate;
    

    void run() {
        if(logger is null) {
            this.logger = new FileLogger(".logs/%s.log".format(name.toLower()));
            this.logger.setEagerFlushing(true);
            this.ownedLogger = true;
        }

        logger.log("%sRunning", logPrefix);

        uint idleCount;
        try{
            while(!shuttingDown.get()) {
                uint numEvents = consumeEvents();

                // Do some work
                bool workDone = workDelegate();

                if(numEvents == 0 && !workDone) {
                    idleCount++;
                }

                // If we have spun round a few times without doing anything then hibernate for a bit
                if(!shuttingDown.get() && idleCount >= idleLimit) {
                    Thread.sleep(dur!"msecs"(idleSleepTimeMs));
                    idleCount = 0;
                }
            }
        }catch(Exception e) {
            logger.log("%sException: %s", logPrefix, e.msg);
        }
        logger.log("%sExiting", logPrefix);
    }
    uint consumeEvents() {
        EventMsg[N] buffer;
        uint total;
        uint count;
        do {
            count = messages.drain(buffer);
            foreach(m; buffer[0..count]) {
                messageProcessorDelegate(m);
            }
            total += count;

            if(!greedyConsumeEvents) {
                break;
            }
        }while(!shuttingDown.get() && count > 0);
        return total;
    }
}
