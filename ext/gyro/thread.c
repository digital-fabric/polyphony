#include "gyro.h"

static VALUE cQueue;

static ID ID_create_event_selector;
static ID ID_empty;
static ID ID_fiber_ref_count;
static ID ID_ivar_event_selector_proc;
static ID ID_ivar_event_selector;
static ID ID_ivar_main_fiber;
static ID ID_pop;
static ID ID_push;
static ID ID_run_queue;
// static ID ID_run_queue_head;
// static ID ID_run_queue_tail;
static ID ID_runnable_next;
static ID ID_stop;

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
  rb_ivar_set(self, ID_ivar_main_fiber, rb_fiber_current());
  rb_ivar_set(self, ID_fiber_ref_count, INT2NUM(0));
  VALUE queue = rb_ary_new();
  rb_ivar_set(self, ID_run_queue, queue);
  VALUE selector = rb_funcall(rb_cThread, ID_create_event_selector, 1, self);
  rb_ivar_set(self, ID_ivar_event_selector, selector);

  return self;
}

static VALUE Thread_stop_event_selector(VALUE self) {
  VALUE selector = rb_ivar_get(self, ID_ivar_event_selector);
  if (selector != Qnil) {
    rb_funcall(selector, ID_stop, 0);
  }

  return self;
}

VALUE Thread_ref(VALUE self) {
  VALUE count = rb_ivar_get(self, ID_fiber_ref_count);
  int new_count = NUM2INT(count) + 1;
  rb_ivar_set(self, ID_fiber_ref_count, INT2NUM(new_count));
  return self;
}

VALUE Thread_unref(VALUE self) {
  VALUE count = rb_ivar_get(self, ID_fiber_ref_count);
  int new_count = NUM2INT(count) - 1;
  rb_ivar_set(self, ID_fiber_ref_count, INT2NUM(new_count));
  return self;
}

int Thread_fiber_ref_count(VALUE self) {
  VALUE count = rb_ivar_get(self, ID_fiber_ref_count);
  return NUM2INT(count);
}

void Thread_fiber_reset_ref_count(VALUE self) {
  rb_ivar_set(self, ID_fiber_ref_count, INT2NUM(0));
}

static VALUE SYM_scheduled_fibers;
static VALUE SYM_pending_watchers;

static VALUE Thread_fiber_scheduling_stats(VALUE self) {
  VALUE stats = rb_hash_new();
  VALUE queue = rb_ivar_get(self, ID_run_queue);
  VALUE selector = rb_ivar_get(self, ID_ivar_event_selector);
  
  long scheduled_count = RARRAY_LEN(queue);
  rb_hash_aset(stats, SYM_scheduled_fibers, INT2NUM(scheduled_count));

  long pending_count = Gyro_Selector_pending_count(selector);
  rb_hash_aset(stats, SYM_pending_watchers, INT2NUM(pending_count));

  return stats;
}

VALUE Thread_schedule_fiber(VALUE self, VALUE fiber, VALUE value) {
  FIBER_TRACE(3, SYM_fiber_schedule, fiber, value);
  // if fiber is already scheduled, just set the scheduled value, then return
  rb_ivar_set(fiber, ID_runnable_value, value);
  if (rb_ivar_get(fiber, ID_runnable) != Qnil) {
    return self;
  }

  VALUE queue = rb_ivar_get(self, ID_run_queue);
  rb_ary_push(queue, fiber);
  rb_ivar_set(fiber, ID_runnable, Qtrue);
  return self;
}

VALUE Thread_switch_fiber(VALUE self) {
  VALUE current_fiber = rb_fiber_current();
  if (__tracing_enabled__) {
    if (rb_ivar_get(current_fiber, ID_ivar_running) != Qfalse) {
      rb_funcall(rb_cObject, ID_fiber_trace, 2, SYM_fiber_switchpoint, current_fiber);
    }
  }
  VALUE queue = rb_ivar_get(self, ID_run_queue);
  VALUE selector = rb_ivar_get(self, ID_ivar_event_selector);

  VALUE next_fiber;

  while (1) {
    next_fiber = rb_ary_shift(queue);
    // if (break_flag != 0) {
    //   return Qnil;
    // }
    int ref_count = Thread_fiber_ref_count(self);
    if (next_fiber != Qnil) {
      if (ref_count > 0) {
        Gyro_Selector_run_no_wait(selector, current_fiber, RARRAY_LEN(queue));
      }
      break;
    }
    if (ref_count == 0) {
      break;
    }

    Gyro_Selector_run(selector, current_fiber);
  }

  if (next_fiber == Qnil) {
    return Qnil;
  }

  // run next fiber
  VALUE value = rb_ivar_get(next_fiber, ID_runnable_value);
  FIBER_TRACE(3, SYM_fiber_run, next_fiber, value);

  rb_ivar_set(next_fiber, ID_runnable, Qnil);
  RB_GC_GUARD(next_fiber);
  RB_GC_GUARD(value);
  return rb_funcall(next_fiber, ID_transfer, 1, value);
}

VALUE Thread_reset_fiber_scheduling(VALUE self) {
  VALUE queue = rb_ivar_get(self, ID_run_queue);
  rb_ary_clear(queue);
  Thread_fiber_reset_ref_count(self);
  return self;
}

VALUE Thread_post_fork(VALUE self) {
  ev_loop_fork(EV_DEFAULT);
  Thread_setup_fiber_scheduling(self);
  return self;
}

VALUE Fiber_await() {
  VALUE thread = rb_thread_current();
  Thread_ref(thread);
  VALUE ret = Thread_switch_fiber(thread);
  Thread_unref(thread);
  RB_GC_GUARD(ret);
  return ret;
}

VALUE Thread_current_event_selector() {
  return rb_ivar_get(rb_thread_current(), ID_ivar_event_selector);
}

void Init_Thread() {
  cQueue = rb_const_get(rb_cObject, rb_intern("Queue"));

  rb_define_singleton_method(rb_cThread, "event_selector=", Thread_event_selector_set_proc, 1);
  rb_define_singleton_method(rb_cThread, "create_event_selector", Thread_create_event_selector, 1);

  rb_define_method(rb_cThread, "fiber_ref", Thread_ref, 0);
  rb_define_method(rb_cThread, "fiber_unref", Thread_unref, 0);

  rb_define_method(rb_cThread, "setup_fiber_scheduling", Thread_setup_fiber_scheduling, 0);
  rb_define_method(rb_cThread, "stop_event_selector", Thread_stop_event_selector, 0);
  rb_define_method(rb_cThread, "reset_fiber_scheduling", Thread_reset_fiber_scheduling, 0);
  rb_define_method(rb_cThread, "fiber_scheduling_stats", Thread_fiber_scheduling_stats, 0);

  rb_define_method(rb_cThread, "schedule_fiber", Thread_schedule_fiber, 2);
  rb_define_method(rb_cThread, "switch_fiber", Thread_switch_fiber, 0);


  ID_create_event_selector    = rb_intern("create_event_selector");
  ID_empty                    = rb_intern("empty?");
  ID_fiber_ref_count          = rb_intern("fiber_ref_count");
  ID_ivar_event_selector      = rb_intern("@event_selector");
  ID_ivar_event_selector_proc = rb_intern("@event_selector_proc");
  ID_ivar_main_fiber          = rb_intern("@main_fiber");
  ID_pop                      = rb_intern("pop");
  ID_push                     = rb_intern("push");
  ID_run_queue                = rb_intern("run_queue");
  ID_runnable_next            = rb_intern("runnable_next");
  ID_stop                     = rb_intern("stop");

  SYM_scheduled_fibers = ID2SYM(rb_intern("scheduled_fibers"));
  SYM_pending_watchers = ID2SYM(rb_intern("pending_watchers"));
  rb_global_variable(&SYM_scheduled_fibers);
  rb_global_variable(&SYM_pending_watchers);
}
