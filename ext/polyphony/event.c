#include "polyphony.h"

typedef struct event {
  VALUE waiting_fiber;
  int signaled;
  VALUE result;
} Event_t;

VALUE cEvent = Qnil;

static void Event_mark(void *ptr) {
  Event_t *event = ptr;
  rb_gc_mark(event->waiting_fiber);
  rb_gc_mark(event->result);
}

static void Event_free(void *ptr) {
  xfree(ptr);
}

static size_t Event_size(const void *ptr) {
  return sizeof(Event_t);
}

static const rb_data_type_t Event_type = {
  "Event",
  {Event_mark, Event_free, Event_size,},
  0, 0, 0
};

static VALUE Event_allocate(VALUE klass) {
  Event_t *event;

  event = ALLOC(Event_t);
  return TypedData_Wrap_Struct(klass, &Event_type, event);
}

static VALUE Event_initialize(VALUE self) {
  Event_t *event = RTYPEDDATA_DATA(self);

  event->waiting_fiber = Qnil;
  event->signaled = 0;
  event->result = Qnil;

  return self;
}

VALUE Event_signal(int argc, VALUE *argv, VALUE self) {
  VALUE value = argc > 0 ? argv[0] : Qnil;
  Event_t *event = RTYPEDDATA_DATA(self);

  if (event->signaled) goto done;

  event->signaled = 1;
  event->result = value;

  if (event->waiting_fiber != Qnil) {
    Fiber_make_runnable(event->waiting_fiber, value);
    event->waiting_fiber = Qnil;
  }

done:
  return self;
}

VALUE Event_await(VALUE self) {
  Event_t *event = RTYPEDDATA_DATA(self);
  VALUE switchpoint_result;
  VALUE backend;

  if (event->waiting_fiber != Qnil)
    rb_raise(rb_eRuntimeError, "Event is already awaited by another fiber");

  if (event->signaled) {
    VALUE result = event->result;
    event->signaled = 0;
    event->result = Qnil;
    return result;
  }

  backend = rb_ivar_get(rb_thread_current(), ID_ivar_backend);
  event->waiting_fiber = rb_fiber_current();
  switchpoint_result = Backend_wait_event(backend, Qnil);
  event->waiting_fiber = Qnil;
  event->signaled = 0;
  event->result = Qnil;

  RAISE_IF_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(backend);
  RB_GC_GUARD(switchpoint_result);

  return switchpoint_result;
}

void Init_Event(void) {
  cEvent = rb_define_class_under(mPolyphony, "Event", rb_cObject);
  rb_define_alloc_func(cEvent, Event_allocate);

  rb_define_method(cEvent, "initialize", Event_initialize, 0);
  rb_define_method(cEvent, "await", Event_await, 0);
  rb_define_method(cEvent, "signal", Event_signal, -1);
}
