#include "polyphony.h"

ID ID_deactivate_all_watchers_post_fork;
ID ID_ivar_backend;
ID ID_ivar_join_wait_queue;
ID ID_ivar_main_fiber;
ID ID_ivar_terminated;
ID ID_ivar_runqueue;
ID ID_stop;

static VALUE Thread_setup_fiber_scheduling(VALUE self) {
  VALUE runqueue = rb_funcall(cRunqueue, ID_new, 0);

  rb_ivar_set(self, ID_ivar_main_fiber, rb_fiber_current());
  rb_ivar_set(self, ID_ivar_runqueue, runqueue);

  return self;
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

  pending_count = Backend_pending_count(backend);
  rb_hash_aset(stats, SYM_pending_watchers, INT2NUM(pending_count));

  return stats;
}

void schedule_fiber(VALUE self, VALUE fiber, VALUE value, int prioritize) {
  VALUE runqueue;
  int already_runnable;

  if (rb_fiber_alive_p(fiber) != Qtrue) return;
  already_runnable = rb_ivar_get(fiber, ID_ivar_runnable) != Qnil;

  COND_TRACE(3, SYM_fiber_schedule, fiber, value);
  runqueue = rb_ivar_get(self, ID_ivar_runqueue);
  (prioritize ? Runqueue_unshift : Runqueue_push)(runqueue, fiber, value, already_runnable);
  if (!already_runnable) {
    rb_ivar_set(fiber, ID_ivar_runnable, Qtrue);
    if (rb_thread_current() != self) {
      // If the fiber scheduling is done across threads, we need to make sure the
      // target thread is woken up in case it is in the middle of running its
      // event selector. Otherwise it's gonna be stuck waiting for an event to
      // happen, not knowing that it there's already a fiber ready to run in its
      // run queue.
      VALUE backend = rb_ivar_get(self,ID_ivar_backend);
      Backend_wakeup(backend);
    }
  }
}

VALUE Thread_schedule_fiber(VALUE self, VALUE fiber, VALUE value) {
  schedule_fiber(self, fiber, value, 0);
  return self;
}

VALUE Thread_schedule_fiber_with_priority(VALUE self, VALUE fiber, VALUE value) {
  schedule_fiber(self, fiber, value, 1);
  return self;
}

VALUE Thread_switch_fiber(VALUE self) {
  VALUE current_fiber = rb_fiber_current();
  VALUE runqueue = rb_ivar_get(self, ID_ivar_runqueue);
  runqueue_entry next;
  VALUE backend = rb_ivar_get(self, ID_ivar_backend);
  unsigned int pending_count = Backend_pending_count(backend);
  unsigned int backend_was_polled = 0;

  if (__tracing_enabled__ && (rb_ivar_get(current_fiber, ID_ivar_running) != Qfalse))
    TRACE(2, SYM_fiber_switchpoint, current_fiber);

  while (1) {
    next = Runqueue_shift(runqueue);
    if (next.fiber != Qnil) {
      if (!backend_was_polled && pending_count) {
        // this prevents event starvation in case the run queue never empties
        Backend_poll(backend, Qtrue, current_fiber, runqueue);
      }
      break;
    }
    if (pending_count == 0) break;

    Backend_poll(backend, Qnil, current_fiber, runqueue);
    backend_was_polled = 1;
  }

  if (next.fiber == Qnil) return Qnil;

  // run next fiber
  COND_TRACE(3, SYM_fiber_run, next.fiber, next.value);

  rb_ivar_set(next.fiber, ID_ivar_runnable, Qnil);
  RB_GC_GUARD(next.fiber);
  RB_GC_GUARD(next.value);
  return (next.fiber == current_fiber) ?
    next.value : FIBER_TRANSFER(next.fiber, next.value);
}

VALUE Thread_fiber_schedule_and_wakeup(VALUE self, VALUE fiber, VALUE resume_obj) {
  VALUE backend = rb_ivar_get(self, ID_ivar_backend);
  if (fiber != Qnil) {
    Thread_schedule_fiber_with_priority(self, fiber, resume_obj);
  }

  if (Backend_wakeup(backend) == Qnil) {
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
  rb_define_method(rb_cThread, "fiber_scheduling_stats", Thread_fiber_scheduling_stats, 0);
  rb_define_method(rb_cThread, "schedule_and_wakeup", Thread_fiber_schedule_and_wakeup, 2);

  rb_define_method(rb_cThread, "schedule_fiber", Thread_schedule_fiber, 2);
  rb_define_method(rb_cThread, "schedule_fiber_with_priority",
    Thread_schedule_fiber_with_priority, 2);
  rb_define_method(rb_cThread, "switch_fiber", Thread_switch_fiber, 0);

  rb_define_method(rb_cThread, "debug!", Thread_debug, 0);

  ID_deactivate_all_watchers_post_fork  = rb_intern("deactivate_all_watchers_post_fork");
  ID_ivar_backend                       = rb_intern("@backend");
  ID_ivar_join_wait_queue               = rb_intern("@join_wait_queue");
  ID_ivar_main_fiber                    = rb_intern("@main_fiber");
  ID_ivar_terminated                    = rb_intern("@terminated");
  ID_ivar_runqueue                      = rb_intern("@runqueue");
  ID_stop                               = rb_intern("stop");

  SYM_scheduled_fibers = ID2SYM(rb_intern("scheduled_fibers"));
  SYM_pending_watchers = ID2SYM(rb_intern("pending_watchers"));
  rb_global_variable(&SYM_scheduled_fibers);
  rb_global_variable(&SYM_pending_watchers);
}
