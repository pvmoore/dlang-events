module events.EventConsumer;

import events.all;

/**
 * A mechanism for consuming events from the event system without using the event thread(s)
 * or having to maintain their own queue.
 *
 * The consumer calls processMessages() to process up to N events at a time.
 *
 * eg.
 *
 * auto events = new EventConsumer!8 consumer("myConsumer", 0b0110, makeSPSCQueue!EventMsg(1024*1024));
 * auto num = events.processMessages((msg) { ... });
 */
final class EventConsumer(uint N) {
public:
    this(string name, ulong eventMask, IQueue!EventMsg messages) {
        this.name = name;
        this.messages = messages;
        getEvents().subscribe(name, eventMask, messages);
    }
    uint processMessages(void delegate(EventMsg) handler) {
        uint count = messages.drain(buffer);
        foreach(m; buffer[0..count]) {
            handler(m);
        }
        return count;
    }
private:
    string name;
    IQueue!EventMsg messages;
    EventMsg[N] buffer;
}
