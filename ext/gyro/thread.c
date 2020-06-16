#include "gyro.h"

static VALUE cQueue;

static ID ID_deactivate_all_watchers_post_fork;
static ID ID_empty;
static ID ID_fiber_ref_count;
static ID ID_ivar_agent;
static ID ID_ivar_join_wait_queue;
static ID ID_ivar_main_fiber;
static ID ID_ivar_result;
static ID ID_ivar_terminated;
static ID ID_pop;
static ID ID_push;
static ID ID_run_queue;
static ID ID_runnable_next;
static ID ID_stop;

static VALUE Thread_setup_fiber_scheduling(VALUE self) {
  VALUE queue;
  
  rb_ivar_set(self, ID_ivar_main_fiber, rb_fiber_current());
  rb_ivar_set(self, ID_fiber_ref_count, INT2NUM(0));
  queue = rb_ary_new();
  rb_ivar_set(self, ID_run_queue, queue);

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
  long pending_count;

  long scheduled_count = RARRAY_LEN(queue);
  rb_hash_aset(stats, SYM_scheduled_fibers, INT2NUM(scheduled_count));

  pending_count = 0; // should be set to number of pending libev watchers
  rb_hash_aset(stats, SYM_pending_watchers, INT2NUM(pending_count));

  return stats;
}

VALUE Thread_schedule_fiber(VALUE self, VALUE fiber, VALUE value) {
  VALUE queue;

  if (rb_fiber_alive_p(fiber) != Qtrue) return self;

  FIBER_TRACE(3, SYM_fiber_schedule, fiber, value);
  // if fiber is already scheduled, just set the scheduled value, then return
  rb_ivar_set(fiber, ID_runnable_value, value);
  if (rb_ivar_get(fiber, ID_runnable) != Qnil) {
    return self;
  }

  queue = rb_ivar_get(self, ID_run_queue);
  rb_ary_push(queue, fiber);
  rb_ivar_set(fiber, ID_runnable, Qtrue);

  if (rb_thread_current() != self) {
    // if the fiber scheduling is done across threads, we need to make sure the
    // target thread is woken up in case it is in the middle of running its
    // event selector. Otherwise it's gonna be stuck waiting for an event to
    // happen, not knowing that it there's already a fiber ready to run in its
    // run queue.
    VALUE agent = rb_ivar_get(self,ID_ivar_agent);
    LibevAgent_break(agent);
  }
  return self;
}

VALUE Thread_schedule_fiber_with_priority(VALUE self, VALUE fiber, VALUE value) {
  VALUE queue;

  if (rb_fiber_alive_p(fiber) != Qtrue) return self;

  FIBER_TRACE(3, SYM_fiber_schedule, fiber, value);
  rb_ivar_set(fiber, ID_runnable_value, value);

  queue = rb_ivar_get(self, ID_run_queue);

  // if fiber is already scheduled, remove it from the run queue
  if (rb_ivar_get(fiber, ID_runnable) != Qnil) {
    rb_ary_delete(queue, fiber);
  } else {
    rb_ivar_set(fiber, ID_runnable, Qtrue);
  }

  // the fiber is given priority by putting it at the front of the run queue
  rb_ary_unshift(queue, fiber);

  if (rb_thread_current() != self) {
    // if the fiber scheduling is done across threads, we need to make sure the
    // target thread is woken up in case it is in the middle of running its
    // event loop. Otherwise it's gonna be stuck waiting for an event to
    // happen, not knowing that it there's already a fiber ready to run in its
    // run queue.
    VALUE agent = rb_ivar_get(self, ID_ivar_agent);
    LibevAgent_break(agent);
  }
  return self;
}

VALUE Thread_switch_fiber(VALUE self) {
  VALUE current_fiber = rb_fiber_current();
  VALUE queue = rb_ivar_get(self, ID_run_queue);
  VALUE next_fiber;
  VALUE value;
  VALUE agent = rb_ivar_get(self, ID_ivar_agent);
  int ref_count;

  if (__tracing_enabled__) {
    if (rb_ivar_get(current_fiber, ID_ivar_running) != Qfalse) {
      rb_funcall(rb_cObject, ID_fiber_trace, 2, SYM_fiber_switchpoint, current_fiber);
    }
  }

  while (1) {
    ref_count = Thread_fiber_ref_count(self);
    next_fiber = rb_ary_shift(queue);
    if (next_fiber != Qnil) {
      if (ref_count > 0) {
        // this mechanism prevents event starvation in case the run queue never
        // empties
        LibevAgent_poll(agent, Qtrue, current_fiber, queue);
      }
      break;
    }
    if (ref_count == 0) break;

    LibevAgent_poll(agent, Qnil, current_fiber, queue);
  }

  if (next_fiber == Qnil) return Qnil;

  // run next fiber
  value = rb_ivar_get(next_fiber, ID_runnable_value);
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

VALUE Gyro_switchpoint() {
  VALUE ret;
  VALUE thread = rb_thread_current();
  Thread_ref(thread);
  ret = Thread_switch_fiber(thread);
  Thread_unref(thread);
  RB_GC_GUARD(ret);
  return ret;
}

VALUE Thread_fiber_break_out_of_ev_loop(VALUE self, VALUE fiber, VALUE resume_obj) {
  VALUE agent = rb_ivar_get(self, ID_ivar_agent);
  if (fiber != Qnil) {
    Thread_schedule_fiber_with_priority(self, fiber, resume_obj);
  }

  if (LibevAgent_break(agent) == Qnil) {
    // we're not inside the ev_loop, so we just do a switchpoint
    Thread_switch_fiber(self);
  }

  return self;
}

void Init_Thread() {
  cQueue = rb_const_get(rb_cObject, rb_intern("Queue"));

  rb_define_method(rb_cThread, "fiber_ref", Thread_ref, 0);
  rb_define_method(rb_cThread, "fiber_unref", Thread_unref, 0);

  rb_define_method(rb_cThread, "setup_fiber_scheduling", Thread_setup_fiber_scheduling, 0);
  rb_define_method(rb_cThread, "reset_fiber_scheduling", Thread_reset_fiber_scheduling, 0);
  rb_define_method(rb_cThread, "fiber_scheduling_stats", Thread_fiber_scheduling_stats, 0);
  rb_define_method(rb_cThread, "break_out_of_ev_loop", Thread_fiber_break_out_of_ev_loop, 2);

  rb_define_method(rb_cThread, "schedule_fiber", Thread_schedule_fiber, 2);
  rb_define_method(rb_cThread, "schedule_fiber_with_priority",
    Thread_schedule_fiber_with_priority, 2);
  rb_define_method(rb_cThread, "switch_fiber", Thread_switch_fiber, 0);

  ID_deactivate_all_watchers_post_fork = rb_intern("deactivate_all_watchers_post_fork");
  ID_empty                    = rb_intern("empty?");
  ID_fiber_ref_count          = rb_intern("fiber_ref_count");
  ID_ivar_agent               = rb_intern("@agent");
  ID_ivar_join_wait_queue     = rb_intern("@join_wait_queue");
  ID_ivar_main_fiber          = rb_intern("@main_fiber");
  ID_ivar_result              = rb_intern("@result");
  ID_ivar_terminated          = rb_intern("@terminated");
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
