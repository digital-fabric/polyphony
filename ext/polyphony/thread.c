#include "polyphony.h"
#include "backend_common.h"

ID ID_deactivate_all_watchers_post_fork;
ID ID_ivar_backend;
ID ID_ivar_join_wait_queue;
ID ID_ivar_main_fiber;
ID ID_ivar_terminated;
ID ID_stop;

static VALUE Thread_setup_fiber_scheduling(VALUE self) {
  rb_ivar_set(self, ID_ivar_main_fiber, rb_fiber_current());
  return self;
}

static VALUE SYM_runqueue_length;
static VALUE SYM_runqueue_max_length;
static VALUE SYM_op_count;
static VALUE SYM_switch_count;
static VALUE SYM_poll_count;
static VALUE SYM_pending_ops;

static VALUE Thread_fiber_scheduling_stats(VALUE self) {
  struct backend_stats backend_stats = Backend_stats(rb_ivar_get(self, ID_ivar_backend));

  VALUE stats = rb_hash_new();
  rb_hash_aset(stats, SYM_runqueue_length, INT2NUM(backend_stats.runqueue_length));
  rb_hash_aset(stats, SYM_runqueue_max_length, INT2NUM(backend_stats.runqueue_max_length));
  rb_hash_aset(stats, SYM_op_count, INT2NUM(backend_stats.op_count));
  rb_hash_aset(stats, SYM_switch_count, INT2NUM(backend_stats.switch_count));
  rb_hash_aset(stats, SYM_poll_count, INT2NUM(backend_stats.poll_count));
  rb_hash_aset(stats, SYM_pending_ops, INT2NUM(backend_stats.pending_ops));
  return stats;
}

inline void schedule_fiber(VALUE self, VALUE fiber, VALUE value, int prioritize) {
  Backend_schedule_fiber(self, rb_ivar_get(self, ID_ivar_backend), fiber, value, prioritize);
}

VALUE Thread_fiber_unschedule(VALUE self, VALUE fiber) {
  Backend_unschedule_fiber(rb_ivar_get(self, ID_ivar_backend), fiber);
  return self;
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
  return Backend_switch_fiber(rb_ivar_get(self, ID_ivar_backend));
}

VALUE Thread_fiber_schedule_and_wakeup(VALUE self, VALUE fiber, VALUE resume_obj) {
  if (fiber != Qnil) {
    Thread_schedule_fiber_with_priority(self, fiber, resume_obj);
  }

  if (Backend_wakeup(rb_ivar_get(self, ID_ivar_backend)) == Qnil) {
    // we're not inside the ev_loop, so we just do a switchpoint
    Thread_switch_fiber(self);
  }

  return self;
}

VALUE Thread_debug(VALUE self) {
  rb_ivar_set(self, rb_intern("@__debug__"), Qtrue);
  return self;
}

VALUE Thread_class_backend(VALUE _self) {
  return rb_ivar_get(rb_thread_current(), ID_ivar_backend);
}

void Init_Thread() {
  rb_define_method(rb_cThread, "setup_fiber_scheduling", Thread_setup_fiber_scheduling, 0);
  rb_define_method(rb_cThread, "fiber_scheduling_stats", Thread_fiber_scheduling_stats, 0);
  rb_define_method(rb_cThread, "schedule_and_wakeup", Thread_fiber_schedule_and_wakeup, 2);

  rb_define_method(rb_cThread, "schedule_fiber", Thread_schedule_fiber, 2);
  rb_define_method(rb_cThread, "schedule_fiber_with_priority",
    Thread_schedule_fiber_with_priority, 2);
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

  SYM_runqueue_length = ID2SYM(rb_intern("runqueue_length"));
  SYM_runqueue_max_length = ID2SYM(rb_intern("runqueue_max_length"));
  SYM_op_count = ID2SYM(rb_intern("op_count"));
  SYM_switch_count = ID2SYM(rb_intern("switch_count"));
  SYM_poll_count = ID2SYM(rb_intern("poll_count"));
  SYM_pending_ops = ID2SYM(rb_intern("pending_ops"));
  
  rb_global_variable(&SYM_runqueue_length);
  rb_global_variable(&SYM_runqueue_max_length);
  rb_global_variable(&SYM_op_count);
  rb_global_variable(&SYM_switch_count);
  rb_global_variable(&SYM_poll_count);
  rb_global_variable(&SYM_pending_ops);
}
