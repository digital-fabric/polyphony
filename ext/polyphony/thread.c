#include "polyphony.h"
#include "backend_common.h"

ID ID_deactivate_all_watchers_post_fork;
ID ID_ivar_backend;
ID ID_ivar_join_wait_queue;
ID ID_ivar_main_fiber;
ID ID_ivar_terminated;
ID ID_stop;

/* :nop-doc: */

static VALUE Thread_setup_fiber_scheduling(VALUE self) {
  rb_ivar_set(self, ID_ivar_main_fiber, rb_fiber_current());
  return self;
}

inline void schedule_fiber(VALUE self, VALUE fiber, VALUE value, int prioritize) {
  Backend_schedule_fiber(self, rb_ivar_get(self, ID_ivar_backend), fiber, value, prioritize);
}

/* call-seq:
 *   thread.unschedule_fiber(fiber)
 *
 * Removes the given fiber from the thread's runqueue.
 * 
 * @param fiber [Fiber] fiber to unschedule
 * @return [Thread] self
 */

VALUE Thread_fiber_unschedule(VALUE self, VALUE fiber) {
  Backend_unschedule_fiber(rb_ivar_get(self, ID_ivar_backend), fiber);
  return self;
}

inline void Thread_schedule_fiber(VALUE self, VALUE fiber, VALUE value) {
  Backend_schedule_fiber(self, rb_ivar_get(self, ID_ivar_backend), fiber, value, 0);

  // schedule_fiber(self, fiber, value, 0);
}

inline void Thread_schedule_fiber_with_priority(VALUE self, VALUE fiber, VALUE value) {
  Backend_schedule_fiber(self, rb_ivar_get(self, ID_ivar_backend), fiber, value, 1);

  // schedule_fiber(self, fiber, value, 1);
}

/* call-seq:
 *   thread.switch_fiber()
 *
 * Switches to the next fiber in the thread's runqueue.
 * 
 * @return [void]
 */

VALUE Thread_switch_fiber(VALUE self) {
  return Backend_switch_fiber(rb_ivar_get(self, ID_ivar_backend));
}

/* @!visibility private */

VALUE Thread_fiber_schedule_and_wakeup(VALUE self, VALUE fiber, VALUE resume_obj) {
  if (fiber != Qnil) {
    Thread_schedule_fiber_with_priority(self, fiber, resume_obj);
  }

  VALUE backend = rb_ivar_get(self, ID_ivar_backend);
  if (Backend_wakeup(backend) == Qnil) {
    // we're not inside Backend_poll, so we just do a switchpoint
    Backend_switch_fiber(backend);
  }

  return self;
}

/* @!visibility private */

VALUE Thread_debug(VALUE self) {
  rb_ivar_set(self, rb_intern("@__debug__"), Qtrue);
  return self;
}

/* call-seq:
 *   Thread.backend
 *
 * Returns the backend for the current thread.
 * 
 * @return [Polyphony::Backend] backend for the current thread
 */

VALUE Thread_class_backend(VALUE _self) {
  return rb_ivar_get(rb_thread_current(), ID_ivar_backend);
}

void Init_Thread(void) {
  rb_define_method(rb_cThread, "setup_fiber_scheduling", Thread_setup_fiber_scheduling, 0);
  rb_define_method(rb_cThread, "schedule_and_wakeup", Thread_fiber_schedule_and_wakeup, 2);
  rb_define_method(rb_cThread, "switch_fiber", Thread_switch_fiber, 0);
  rb_define_method(rb_cThread, "fiber_unschedule", Thread_fiber_unschedule, 1);

  rb_define_singleton_method(rb_cThread, "backend", Thread_class_backend, 0);

  rb_define_method(rb_cThread, "debug!", Thread_debug, 0);

  ID_deactivate_all_watchers_post_fork  = rb_intern("deactivate_all_watchers_post_fork");
  ID_ivar_backend                       = rb_intern("@backend");
  ID_ivar_join_wait_queue               = rb_intern("@join_wait_queue");
  ID_ivar_main_fiber                    = rb_intern("@main_fiber");
  ID_ivar_terminated                    = rb_intern("@terminated");
  ID_stop                               = rb_intern("stop");
}
