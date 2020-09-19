#include "polyphony.h"

ID ID_deactivate_all_watchers_post_fork;
ID ID_ivar_backend;
ID ID_ivar_join_wait_queue;
ID ID_ivar_main_fiber;
ID ID_ivar_result;
ID ID_ivar_terminated;
ID ID_ivar_runqueue;
ID ID_stop;

static VALUE Thread_setup_fiber_scheduling(VALUE self) {
  VALUE runqueue = rb_funcall(cRunqueue, ID_new, 0);

  rb_ivar_set(self, ID_ivar_main_fiber, rb_fiber_current());
  rb_ivar_set(self, ID_ivar_runqueue, runqueue);

  return self;
}

int Thread_fiber_ref_count(VALUE self) {
  VALUE backend = rb_ivar_get(self, ID_ivar_backend);
  return NUM2INT(__BACKEND__.ref_count(backend));
}

inline void Thread_fiber_reset_ref_count(VALUE self) {
  VALUE backend = rb_ivar_get(self, ID_ivar_backend);
  __BACKEND__.reset_ref_count(backend);
}

static VALUE SYM_scheduled_fibers;
static VALUE SYM_pending_watchers;

static VALUE Thread_fiber_scheduling_stats(VALUE self) {
  VALUE backend = rb_ivar_get(self,ID_ivar_backend);
  VALUE stats = rb_hash_new();
  VALUE runqueue = rb_ivar_get(self, ID_ivar_runqueue);
  long pending_count;

  long scheduled_count = Runqueue_len(runqueue);
  rb_hash_aset(stats, SYM_scheduled_fibers, INT2NUM(scheduled_count));

  pending_count = __BACKEND__.pending_count(backend);
  rb_hash_aset(stats, SYM_pending_watchers, INT2NUM(pending_count));

  return stats;
}

VALUE Thread_schedule_fiber(VALUE self, VALUE fiber, VALUE value) {
  VALUE queue;

  if (rb_fiber_alive_p(fiber) != Qtrue) return self;

  int already_runnable = rb_ivar_get(fiber, ID_runnable) != Qnil;

  if (already_runnable) {
    VALUE current_runnable_value = rb_ivar_get(fiber, ID_runnable_value);

    // If the fiber is already runnable and the runnable value is an exception,
    // we don't update the value, in order to prevent a race condition where
    // exceptions will be lost (see issue #33)
    if (TEST_EXCEPTION(current_runnable_value)) return self;
  }

  rb_ivar_set(fiber, ID_runnable_value, value);
  COND_TRACE(3, SYM_fiber_schedule, fiber, value);

  if (!already_runnable) {
    runqueue = rb_ivar_get(self, ID_ivar_runqueue);
    Queue_push(queue, fiber);
    rb_ivar_set(fiber, ID_runnable, Qtrue);

    if (rb_thread_current() != self) {
      // If the fiber scheduling is done across threads, we need to make sure the
      // target thread is woken up in case it is in the middle of running its
      // event selector. Otherwise it's gonna be stuck waiting for an event to
      // happen, not knowing that it there's already a fiber ready to run in its
      // run queue.
      VALUE backend = rb_ivar_get(self,ID_ivar_backend);
      __BACKEND__.wakeup(backend);
    }
  }
  return self;
}

VALUE Thread_schedule_fiber_with_priority(VALUE self, VALUE fiber, VALUE value) {
  VALUE queue;

  if (rb_fiber_alive_p(fiber) != Qtrue) return self;

  COND_TRACE(3, SYM_fiber_schedule, fiber, value);
  rb_ivar_set(fiber, ID_runnable_value, value);

  queue = rb_ivar_get(self, ID_ivar_runqueue);

  // if fiber is already scheduled, remove it from the run queue
  if (rb_ivar_get(fiber, ID_runnable) != Qnil) {
    Queue_delete(queue, fiber);
  } else {
    rb_ivar_set(fiber, ID_runnable, Qtrue);
  }

  // the fiber is given priority by putting it at the front of the run queue
  Queue_unshift(queue, fiber);

  if (rb_thread_current() != self) {
    // if the fiber scheduling is done across threads, we need to make sure the
    // target thread is woken up in case it is in the middle of running its
    // event loop. Otherwise it's gonna be stuck waiting for an event to
    // happen, not knowing that it there's already a fiber ready to run in its
    // run queue.
    VALUE backend = rb_ivar_get(self, ID_ivar_backend);
    __BACKEND__.wakeup(backend);
  }
  return self;
}

VALUE Thread_switch_fiber(VALUE self) {
  VALUE current_fiber = rb_fiber_current();
  VALUE queue = rb_ivar_get(self, ID_ivar_runqueue);
  VALUE next_fiber;
  VALUE value;
  VALUE backend = rb_ivar_get(self, ID_ivar_backend);
  int ref_count;
  int backend_was_polled = 0;

  if (__tracing_enabled__ && (rb_ivar_get(current_fiber, ID_ivar_running) != Qfalse))
    TRACE(2, SYM_fiber_switchpoint, current_fiber);

  ref_count = __BACKEND__.ref_count(backend);
  while (1) {
    next_fiber = Queue_shift_no_wait(queue);
    if (next_fiber != Qnil) {
      if (backend_was_polled == 0 && ref_count > 0) {
        // this prevents event starvation in case the run queue never empties
        __BACKEND__.poll(backend, Qtrue, current_fiber, queue);
      }
      break;
    }
    if (ref_count == 0) break;

    __BACKEND__.poll(backend, Qnil, current_fiber, queue);
    backend_was_polled = 1;
  }

  if (next_fiber == Qnil) return Qnil;

  // run next fiber
  value = rb_ivar_get(next_fiber, ID_runnable_value);
  COND_TRACE(3, SYM_fiber_run, next_fiber, value);

  rb_ivar_set(next_fiber, ID_runnable, Qnil);
  RB_GC_GUARD(next_fiber);
  RB_GC_GUARD(value);
  return (next_fiber == current_fiber) ?
    value : rb_funcall(next_fiber, ID_transfer, 1, value);
}

VALUE Thread_run_queue_trace(VALUE self) {
  VALUE queue = rb_ivar_get(self, ID_ivar_runqueue);
  Queue_trace(queue);
  return self;
}

VALUE Thread_reset_fiber_scheduling(VALUE self) {
  VALUE queue = rb_ivar_get(self, ID_ivar_runqueue);
  Queue_clear(queue);
  Thread_fiber_reset_ref_count(self);
  return self;
}

VALUE Thread_fiber_break_out_of_ev_loop(VALUE self, VALUE fiber, VALUE resume_obj) {
  VALUE backend = rb_ivar_get(self, ID_ivar_backend);
  if (fiber != Qnil) {
    Thread_schedule_fiber_with_priority(self, fiber, resume_obj);
  }

  if (__BACKEND__.wakeup(backend) == Qnil) {
    // we're not inside the ev_loop, so we just do a switchpoint
    Thread_switch_fiber(self);
  }

  return self;
}

VALUE Thread_debug(VALUE self) {
  rb_ivar_set(self, rb_intern("@__debug__"), Qtrue);
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
  rb_define_method(rb_cThread, "run_queue_trace", Thread_run_queue_trace, 0);

  rb_define_method(rb_cThread, "debug!", Thread_debug, 0);

  ID_deactivate_all_watchers_post_fork = rb_intern("deactivate_all_watchers_post_fork");
  ID_ivar_backend               = rb_intern("@backend");
  ID_ivar_join_wait_queue     = rb_intern("@join_wait_queue");
  ID_ivar_main_fiber          = rb_intern("@main_fiber");
  ID_ivar_result              = rb_intern("@result");
  ID_ivar_terminated          = rb_intern("@terminated");
  ID_ivar_runqueue            = rb_intern("@runqueue");
  ID_stop                     = rb_intern("stop");

  SYM_scheduled_fibers = ID2SYM(rb_intern("scheduled_fibers"));
  SYM_pending_watchers = ID2SYM(rb_intern("pending_watchers"));
  rb_global_variable(&SYM_scheduled_fibers);
  rb_global_variable(&SYM_pending_watchers);
}
