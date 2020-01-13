#include "gyro.h"

static VALUE cQueue;

static ID ID_create_event_selector;
static ID ID_ivar_event_selector;
static ID ID_ivar_event_selector_proc;
static ID ID_fiber_ref_count;
static ID ID_run_queue;

static ID ID_scheduled;
// static ID ID_scheduled_next;

static ID ID_empty;
static ID ID_pop;
static ID ID_push;

VALUE event_selector_factory_proc(RB_BLOCK_CALL_FUNC_ARGLIST(args, klass)) {
  return rb_funcall(klass, ID_new, 1, rb_ary_entry(args, 0));
}

static VALUE Thread_event_selector_set_proc(VALUE self, VALUE proc) {
  if (!rb_obj_is_proc(proc)) {
    proc = rb_proc_new(event_selector_factory_proc, proc);
  }
  rb_ivar_set(self, ID_ivar_event_selector_proc, proc);
  return self;
}

static VALUE Thread_create_event_selector(VALUE self, VALUE thread) {
  VALUE selector_proc = rb_ivar_get(self, ID_ivar_event_selector_proc);
  if (selector_proc == Qnil) {
    rb_raise(rb_eRuntimeError, "No event_selector_proc defined");
  }

  return rb_funcall(selector_proc, ID_call, 1, thread);
}

static VALUE Thread_setup_fiber_scheduling(VALUE self) {
  rb_ivar_set(self, ID_fiber_ref_count, INT2NUM(0));
  VALUE queue = rb_ary_new();//rb_funcall(cQueue, ID_new, 0);
  rb_ivar_set(self, ID_run_queue, queue);
  VALUE selector = rb_funcall(rb_cThread, ID_create_event_selector, 1, self);
  rb_ivar_set(self, ID_ivar_event_selector, selector);

  return self;
}

static VALUE Thread_stop_event_selector(VALUE self) {
  VALUE selector = rb_ivar_get(self, ID_ivar_event_selector);
  rb_funcall(selector, rb_intern("stop"), 0);

  return self;
}

inline VALUE Thread_ref(VALUE self) {
  VALUE count = rb_ivar_get(self, ID_fiber_ref_count);
  int new_count = NUM2INT(count) + 1;
  rb_ivar_set(self, ID_fiber_ref_count, INT2NUM(new_count));
  return self;
}

inline VALUE Thread_unref(VALUE self) {
  VALUE count = rb_ivar_get(self, ID_fiber_ref_count);
  int new_count = NUM2INT(count) - 1;
  rb_ivar_set(self, ID_fiber_ref_count, INT2NUM(new_count));
  return self;
}

inline int Thread_fiber_ref_count(VALUE self) {
  VALUE count = rb_ivar_get(self, ID_fiber_ref_count);
  return NUM2INT(count);
}

inline void Thread_fiber_reset_ref_count(VALUE self) {
  rb_ivar_set(self, ID_fiber_ref_count, INT2NUM(0));
}

inline VALUE Thread_schedule_fiber(VALUE self, VALUE fiber) {
  VALUE queue = rb_ivar_get(self, ID_run_queue);
  rb_ary_push(queue, fiber);
  return self;
  // return rb_funcall(queue, ID_push, 1, fiber);
}

VALUE Thread_switch_fiber(VALUE self) {
  VALUE queue = rb_ivar_get(self, ID_run_queue);
  VALUE selector = rb_ivar_get(self, ID_ivar_event_selector);
  while (1) {
    // if (break_flag != 0) {
    //   return Qnil;
    // }
    // if (RTEST(rb_funcall(queue, ID_empty, 0))) {
    //   printf("run_queue empty!\n");
    // }
    // if (Thread_fiber_ref_count(self) == 0) {
    //   printf("ref_count = 0\n");
    // }
    if ((RARRAY_LEN(queue) > 0) || (Thread_fiber_ref_count(self) == 0)) {
    // if (!RTEST(rb_funcall(queue, ID_empty, 0)) || (Thread_fiber_ref_count(self) == 0)) {
      break;
    }
    // if ((scheduled_head != Qnil) || (ref_count == 0)) {
    //   break;
    // }

    Gyro_Selector_run(selector);
  }

  VALUE next_fiber;
  if (RARRAY_LEN(queue) == 0) {
  // if (RTEST(rb_funcall(queue, ID_empty, 0))) {
    return Qnil;
  }
  else {
    next_fiber = rb_ary_shift(queue);
    // next_fiber = rb_funcall(queue, ID_pop, 1, Qtrue);
  }

  // return if no fiber is scheduled
  // if (scheduled_head == Qnil) {
  //   return Qnil;
  // }

  // update scheduled linked list refs
  // VALUE next_fiber = scheduled_head;
  // VALUE next_next_fiber = rb_ivar_get(next_fiber, ID_scheduled_next);
  // rb_ivar_set(next_fiber, ID_scheduled_next, Qnil);
  // scheduled_head = next_next_fiber;
  // if (scheduled_head == Qnil) {
  //   scheduled_tail = Qnil;
  // }

  if (rb_fiber_alive_p(next_fiber) != Qtrue) {
    return Qnil;
  }

  // run next fiber
  VALUE value = rb_ivar_get(next_fiber, ID_scheduled_value);
  // rb_ivar_set(next_fiber, ID_scheduled_value, Qnil);
  rb_ivar_set(next_fiber, ID_scheduled, Qnil);

  return rb_funcall(next_fiber, ID_transfer, 1, value);

  RB_GC_GUARD(queue);
  RB_GC_GUARD(next_fiber);
  RB_GC_GUARD(value);
  RB_GC_GUARD(selector);
}

VALUE Thread_reset_fiber_scheduling(VALUE self) {
  VALUE queue = rb_ivar_get(self, ID_run_queue);
  rb_ary_clear(queue);
  Thread_fiber_reset_ref_count(self);
  return self;
}

inline VALUE Fiber_await() {
  VALUE thread = rb_thread_current();
  Thread_ref(thread);
  VALUE ret = Thread_switch_fiber(thread);
  Thread_unref(thread);
  return ret;
}

inline VALUE Thread_current_event_selector() {
  return rb_ivar_get(rb_thread_current(), ID_ivar_event_selector);
}

void Init_Thread() {
  cQueue = rb_const_get(rb_cObject, rb_intern("Queue"));

  rb_define_singleton_method(rb_cThread, "event_selector=", Thread_event_selector_set_proc, 1);
  rb_define_singleton_method(rb_cThread, "create_event_selector", Thread_create_event_selector, 1);

  rb_define_method(rb_cThread, "setup_fiber_scheduling", Thread_setup_fiber_scheduling, 0);
  rb_define_method(rb_cThread, "stop_event_selector", Thread_stop_event_selector, 0);

  rb_define_method(rb_cThread, "fiber_ref", Thread_ref, 0);
  rb_define_method(rb_cThread, "fiber_unref", Thread_unref, 0);

  rb_define_method(rb_cThread, "schedule_fiber", Thread_schedule_fiber, 1);
  rb_define_method(rb_cThread, "switch_fiber", Thread_switch_fiber, 0);

  rb_define_method(rb_cThread, "reset_fiber_scheduling", Thread_reset_fiber_scheduling, 0);

  ID_create_event_selector    = rb_intern("create_event_selector");
  ID_ivar_event_selector      = rb_intern("@event_selector");
  ID_ivar_event_selector_proc = rb_intern("@event_selector_proc");
  ID_fiber_ref_count          = rb_intern("fiber_ref_count");
  ID_run_queue                = rb_intern("run_queue");

  ID_scheduled                = rb_intern("scheduled");
  // ID_scheduled_next           = rb_intern("scheduled_next");
  
  ID_empty                    = rb_intern("empty?");
  ID_pop                      = rb_intern("pop");
  ID_push                     = rb_intern("push");
}
