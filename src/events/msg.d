module events.msg;
/**
 * Usage:
 *
 *  To fire an event:
 *      getEvents().fire(EventMsg(mask, thing);
 *
 *      where thing can be one of:
 *          - ulong, int   -> ulong
 *          - float,double -> double
 *          - ptr          -> void*
 *          - Object       -> void*
 *
 *  To retrieve a payload where m is an EventMsg:
 *
 *      ulong p   = m.get!ulong;
 *      double d  = m.get!double;
 *      MyClass c = m.get!MyClass;
 *      int*      = m.get!(int*);
 *
 *  NB. Any object or pointer stored in an EventMsg
 *      may be garbage collected because the ptr
 *      is turned into a ulong.
 */
import events.all;

final struct EventMsg {
    ulong id;
    ulong payload;

    this(ulong id, ulong p) {
        this.id = id;
        this.payload = p;
    }
    this(ulong id, double p) {
        this.id = id;
        this.payload = p.bitcast!ulong;
    }
    this(ulong id, void* p) {
        this.id = id;
        this.payload = cast(ulong)p;
    }
    this(ulong id, Object p) {
        this.id = id;
        this.payload = cast(ulong)cast(void*)p;
    }

    T get(T)() {
        static if(is(T == double)) {
            return payload.bitcast!double;
        } else static if(is(T == float)) {
            return cast(float)payload.bitcast!double;
        } else static if(isObject!T) {
            return cast(T)cast(void*)payload;
        } else {
            return cast(T)payload;
        }
    }
}
static assert(EventMsg.sizeof==16);
