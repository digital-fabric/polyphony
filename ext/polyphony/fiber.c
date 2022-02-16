#include "polyphony.h"

ID ID_ivar_auto_watcher;
ID ID_ivar_mailbox;
ID ID_ivar_result;
ID ID_ivar_waiting_fibers;

VALUE SYM_dead;
VALUE SYM_running;
VALUE SYM_runnable;
VALUE SYM_waiting;

VALUE SYM_fiber_create;
VALUE SYM_fiber_event_poll_enter;
VALUE SYM_fiber_event_poll_leave;
VALUE SYM_fiber_run;
VALUE SYM_fiber_schedule;
VALUE SYM_fiber_switchpoint;
VALUE SYM_fiber_terminate;

static VALUE Fiber_safe_transfer(int argc, VALUE *argv, VALUE self) {
  VALUE arg = (argc == 0) ? Qnil : argv[0];
  VALUE ret = FIBER_TRANSFER(self, arg);

  RAISE_IF_EXCEPTION(ret);
  RB_GC_GUARD(ret);
  return ret;
}

inline VALUE Fiber_auto_watcher(VALUE self) {
  VALUE watcher;

  watcher = rb_ivar_get(self, ID_ivar_auto_watcher);
  if (watcher == Qnil) {
    watcher = rb_funcall(cEvent, ID_new, 0);
    rb_ivar_set(self, ID_ivar_auto_watcher, watcher);
  }
  return watcher;
}

void Fiber_make_runnable(VALUE fiber, VALUE value) {
  VALUE thread = rb_ivar_get(fiber, ID_ivar_thread);
  if (thread == Qnil) {
    rb_raise(rb_eRuntimeError, "No thread set for fiber");
    // rb_warn("No thread set for fiber");
    return;
  }

  Thread_schedule_fiber(thread, fiber, value);
}

void Fiber_make_runnable_with_priority(VALUE fiber, VALUE value) {
  VALUE thread = rb_ivar_get(fiber, ID_ivar_thread);
  if (thread == Qnil) {
    rb_raise(rb_eRuntimeError, "No thread set for fiber");
    // rb_warn("No thread set for fiber");
    return;
  }

  Thread_schedule_fiber_with_priority(thread, fiber, value);
}

static VALUE Fiber_schedule(int argc, VALUE *argv, VALUE self) {
  VALUE value = (argc == 0) ? Qnil : argv[0];
  Fiber_make_runnable(self, value);
  return self;
}

static VALUE Fiber_schedule_with_priority(int argc, VALUE *argv, VALUE self) {
  VALUE value = (argc == 0) ? Qnil : argv[0];
  Fiber_make_runnable_with_priority(self, value);
  return self;
}

static VALUE Fiber_state(VALUE self) {
  if (!rb_fiber_alive_p(self) || (rb_ivar_get(self, ID_ivar_running) == Qfalse))
    return SYM_dead;
  if (rb_fiber_current() == self) return SYM_running;
  if (rb_ivar_get(self, ID_ivar_runnable) != Qnil) return SYM_runnable;

  return SYM_waiting;
}

VALUE Fiber_send(VALUE self, VALUE value) {
  VALUE mailbox = rb_ivar_get(self, ID_ivar_mailbox);
  if (mailbox == Qnil) {
    mailbox = rb_funcall(cQueue, ID_new, 0);
    rb_ivar_set(self, ID_ivar_mailbox, mailbox);
  }
  Queue_push(mailbox, value);
  return self;
}

VALUE Fiber_receive(VALUE self) {
  VALUE mailbox = rb_ivar_get(self, ID_ivar_mailbox);
  if (mailbox == Qnil) {
    mailbox = rb_funcall(cQueue, ID_new, 0);
    rb_ivar_set(self, ID_ivar_mailbox, mailbox);
  }
  return Queue_shift(0, 0, mailbox);
}

VALUE Fiber_mailbox(VALUE self) {
  VALUE mailbox = rb_ivar_get(self, ID_ivar_mailbox);
  if (mailbox == Qnil) {
    mailbox = rb_funcall(cQueue, ID_new, 0);
    rb_ivar_set(self, ID_ivar_mailbox, mailbox);
  }
  return mailbox;
}

VALUE Fiber_receive_all_pending(VALUE self) {
  VALUE mailbox = rb_ivar_get(self, ID_ivar_mailbox);
  return (mailbox == Qnil) ? rb_ary_new() : Queue_shift_all(mailbox);
}

VALUE Fiber_park(VALUE self) {
  rb_ivar_set(self, ID_ivar_parked, Qtrue);
  Backend_park_fiber(BACKEND(), self);
  return self;
}

VALUE Fiber_unpark(VALUE self) {
  rb_ivar_set(self, ID_ivar_parked, Qnil);
  Backend_unpark_fiber(BACKEND(), self);
  return self;
}

VALUE Fiber_parked_p(VALUE self) {
  return rb_ivar_get(self, ID_ivar_parked);
}

void Init_Fiber() {
  VALUE cFiber = rb_const_get(rb_cObject, rb_intern("Fiber"));
  rb_define_method(cFiber, "safe_transfer", Fiber_safe_transfer, -1);
  rb_define_method(cFiber, "schedule", Fiber_schedule, -1);
  rb_define_method(cFiber, "schedule_with_priority", Fiber_schedule_with_priority, -1);
  rb_define_method(cFiber, "state", Fiber_state, 0);
  rb_define_method(cFiber, "auto_watcher", Fiber_auto_watcher, 0);

  rb_define_method(cFiber, "<<", Fiber_send, 1);
  rb_define_method(cFiber, "send", Fiber_send, 1);
  rb_define_method(cFiber, "receive", Fiber_receive, 0);
  rb_define_method(cFiber, "receive_all_pending", Fiber_receive_all_pending, 0);
  rb_define_method(cFiber, "mailbox", Fiber_mailbox, 0);

  rb_define_method(cFiber, "__park__", Fiber_park, 0);
  rb_define_method(cFiber, "__unpark__", Fiber_unpark, 0);
  rb_define_method(cFiber, "__parked__?", Fiber_parked_p, 0);

  SYM_dead = ID2SYM(rb_intern("dead"));
  SYM_running = ID2SYM(rb_intern("running"));
  SYM_runnable = ID2SYM(rb_intern("runnable"));
  SYM_waiting = ID2SYM(rb_intern("waiting"));
  rb_global_variable(&SYM_dead);
  rb_global_variable(&SYM_running);
  rb_global_variable(&SYM_runnable);
  rb_global_variable(&SYM_waiting);

  ID_ivar_auto_watcher        = rb_intern("@auto_watcher");
  ID_ivar_mailbox             = rb_intern("@mailbox");
  ID_ivar_result              = rb_intern("@result");
  ID_ivar_waiting_fibers      = rb_intern("@waiting_fibers");

  SYM_fiber_create            = ID2SYM(rb_intern("fiber_create"));
  SYM_fiber_event_poll_enter  = ID2SYM(rb_intern("fiber_event_poll_enter"));
  SYM_fiber_event_poll_leave  = ID2SYM(rb_intern("fiber_event_poll_leave"));
  SYM_fiber_run               = ID2SYM(rb_intern("fiber_run"));
  SYM_fiber_schedule          = ID2SYM(rb_intern("fiber_schedule"));
  SYM_fiber_switchpoint       = ID2SYM(rb_intern("fiber_switchpoint"));
  SYM_fiber_terminate         = ID2SYM(rb_intern("fiber_terminate"));

  rb_global_variable(&SYM_fiber_create);
  rb_global_variable(&SYM_fiber_event_poll_enter);
  rb_global_variable(&SYM_fiber_event_poll_leave);
  rb_global_variable(&SYM_fiber_run);
  rb_global_variable(&SYM_fiber_schedule);
  rb_global_variable(&SYM_fiber_switchpoint);
  rb_global_variable(&SYM_fiber_terminate);
}