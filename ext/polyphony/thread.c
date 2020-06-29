#include "polyphony.h"

ID ID_deactivate_all_watchers_post_fork;
ID ID_empty;
ID ID_ivar_agent;
ID ID_ivar_join_wait_queue;
ID ID_ivar_main_fiber;
ID ID_ivar_result;
ID ID_ivar_terminated;
ID ID_pop;
ID ID_push;
ID ID_run_queue;
ID ID_runnable_next;
ID ID_stop;

static VALUE Thread_setup_fiber_scheduling(VALUE self) {
  VALUE queue;
  
  rb_ivar_set(self, ID_ivar_main_fiber, rb_fiber_current());
  queue = rb_ary_new();
  rb_ivar_set(self, ID_run_queue, queue);

  return self;
}

int Thread_fiber_ref_count(VALUE self) {
  VALUE agent = rb_ivar_get(self, ID_ivar_agent);
  return NUM2INT(LibevAgent_ref_count(agent));
}

inline void Thread_fiber_reset_ref_count(VALUE self) {
  VALUE agent = rb_ivar_get(self, ID_ivar_agent);
  LibevAgent_reset_ref_count(agent);
}

static VALUE SYM_scheduled_fibers;
static VALUE SYM_pending_watchers;

static VALUE Thread_fiber_scheduling_stats(VALUE self) {
  VALUE agent = rb_ivar_get(self,ID_ivar_agent);
  VALUE stats = rb_hash_new();
  VALUE queue = rb_ivar_get(self, ID_run_queue);
  long pending_count;

  long scheduled_count = RARRAY_LEN(queue);
  rb_hash_aset(stats, SYM_scheduled_fibers, INT2NUM(scheduled_count));

  pending_count = LibevAgent_pending_count(agent);
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

  ref_count = LibevAgent_ref_count(agent);
  while (1) {
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
  return (next_fiber == current_fiber) ? 
    value : rb_funcall(next_fiber, ID_transfer, 1, value);
}

VALUE Thread_reset_fiber_scheduling(VALUE self) {
  VALUE queue = rb_ivar_get(self, ID_run_queue);
  rb_ary_clear(queue);
  Thread_fiber_reset_ref_count(self);
  return self;
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
