#include "polyphony.h"

ID ID_ivar_auto_watcher;
ID ID_ivar_mailbox;
ID ID_ivar_result;
ID ID_ivar_waiting_fibers;

VALUE SYM_dead;
VALUE SYM_running;
VALUE SYM_runnable;
VALUE SYM_waiting;

VALUE SYM_spin;
VALUE SYM_enter_poll;
VALUE SYM_leave_poll;
VALUE SYM_unblock;
VALUE SYM_schedule;
VALUE SYM_block;
VALUE SYM_terminate;

/* @!visibility private */

static VALUE Fiber_safe_transfer(int argc, VALUE *argv, VALUE self) {
  VALUE arg = (argc == 0) ? Qnil : argv[0];
  VALUE ret = FIBER_TRANSFER(self, arg);

  RAISE_IF_EXCEPTION(ret);
  RB_GC_GUARD(ret);
  return ret;
}

/* @!visibility private */

inline VALUE Fiber_auto_watcher(VALUE self) {
  VALUE watcher;

  watcher = rb_ivar_get(self, ID_ivar_auto_watcher);
  if (watcher == Qnil) {
    watcher = rb_funcall(cEvent, ID_new, 0);
    rb_ivar_set(self, ID_ivar_auto_watcher, watcher);
  }
  return watcher;
}

/* @!visibility private */

inline void Fiber_make_runnable(VALUE fiber, VALUE value) {
  VALUE thread = rb_ivar_get(fiber, ID_ivar_thread);
  if (thread == Qnil) rb_raise(rb_eRuntimeError, "No thread set for fiber");

  Thread_schedule_fiber(thread, fiber, value);
}

/* @!visibility private */

inline void Fiber_make_runnable_with_priority(VALUE fiber, VALUE value) {
  VALUE thread = rb_ivar_get(fiber, ID_ivar_thread);
  if (thread == Qnil) rb_raise(rb_eRuntimeError, "No thread set for fiber");

  Thread_schedule_fiber_with_priority(thread, fiber, value);
}

/* Adds the fiber to the runqueue with the given resume value. If no resume
 * value is given, the fiber will be resumed with `nil`.
 *
 * @overload schedule(value)
 *   @param value [any] resume value
 *   @return [Fiber] scheduled fiber
 * @overload schedule
 *   @return [Fiber] scheduled fiber
 */

static VALUE Fiber_schedule(int argc, VALUE *argv, VALUE self) {
  VALUE value = (argc == 0) ? Qnil : argv[0];
  Fiber_make_runnable(self, value);
  return self;
}

/* Adds the fiber to the head of the runqueue with the given resume value. If no
 * resume value is given, the fiber will be resumed with `nil`.
 *
 * @overload schedule_with_priority(value)
 *   @param value [any] resume value
 *   @return [Fiber] scheduled fiber
 * @overload schedule_with_priority
 *   @return [Fiber] scheduled fiber
 */

static VALUE Fiber_schedule_with_priority(int argc, VALUE *argv, VALUE self) {
  VALUE value = (argc == 0) ? Qnil : argv[0];
  Fiber_make_runnable_with_priority(self, value);
  return self;
}

/* Returns the current state for the fiber, one of the following:
 *
 * - `:running` - the fiber is currently running.
 * - `:runnable` - the fiber is on the runqueue, scheduled to be resumed ("ran").
 * - `:waiting` - the fiber is waiting on some blocking operation to complete,
 *   allowing other fibers to run.
 * - `:dead` - the fiber has finished running.
 *
 * @return [Symbol]
 */

static VALUE Fiber_state(VALUE self) {
  if (!rb_fiber_alive_p(self) || (rb_ivar_get(self, ID_ivar_running) == Qfalse))
    return SYM_dead;
  if (rb_fiber_current() == self) return SYM_running;
  if (rb_ivar_get(self, ID_ivar_runnable) != Qnil) return SYM_runnable;

  return SYM_waiting;
}

/* Sends a message to the given fiber. The message will be added to the fiber's
 * mailbox.
 *
 * @param msg [any]
 * @return [void]
 */

VALUE Fiber_send(VALUE self, VALUE msg) {
  VALUE mailbox = rb_ivar_get(self, ID_ivar_mailbox);
  if (mailbox == Qnil) {
    mailbox = rb_funcall(cQueue, ID_new, 0);
    rb_ivar_set(self, ID_ivar_mailbox, mailbox);
  }
  Queue_push(mailbox, msg);
  return self;
}

/* Receive's a message from the fiber's mailbox. If no message is available,
 * waits for a message to be sent to it.
 *
 * @return [any] received message
 */

VALUE Fiber_receive(VALUE self) {
  VALUE mailbox = rb_ivar_get(self, ID_ivar_mailbox);
  if (mailbox == Qnil) {
    mailbox = rb_funcall(cQueue, ID_new, 0);
    rb_ivar_set(self, ID_ivar_mailbox, mailbox);
  }
  return Queue_shift(0, 0, mailbox);
}

/* Returns the fiber's mailbox.
 *
 * @return [Queue]
 */

VALUE Fiber_mailbox(VALUE self) {
  VALUE mailbox = rb_ivar_get(self, ID_ivar_mailbox);
  if (mailbox == Qnil) {
    mailbox = rb_funcall(cQueue, ID_new, 0);
    rb_ivar_set(self, ID_ivar_mailbox, mailbox);
  }
  return mailbox;
}

/* Receives all messages currently in the fiber's mailbox.
 *
 * @return [Array]
 */

VALUE Fiber_receive_all_pending(VALUE self) {
  VALUE mailbox = rb_ivar_get(self, ID_ivar_mailbox);
  return (mailbox == Qnil) ? rb_ary_new() : Queue_shift_all(mailbox);
}

/* @!visibility private */

VALUE Fiber_park(VALUE self) {
  rb_ivar_set(self, ID_ivar_parked, Qtrue);
  Backend_park_fiber(BACKEND(), self);
  return self;
}

/* @!visibility private */

VALUE Fiber_unpark(VALUE self) {
  rb_ivar_set(self, ID_ivar_parked, Qnil);
  Backend_unpark_fiber(BACKEND(), self);
  return self;
}

/* @!visibility private */

VALUE Fiber_parked_p(VALUE self) {
  return rb_ivar_get(self, ID_ivar_parked);
}

void Init_Fiber(void) {
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

  ID_ivar_auto_watcher    = rb_intern("@auto_watcher");
  ID_ivar_mailbox         = rb_intern("@mailbox");
  ID_ivar_result          = rb_intern("@result");
  ID_ivar_waiting_fibers  = rb_intern("@waiting_fibers");

  SYM_spin                = ID2SYM(rb_intern("spin"));
  SYM_enter_poll          = ID2SYM(rb_intern("enter_poll"));
  SYM_leave_poll          = ID2SYM(rb_intern("leave_poll"));
  SYM_unblock             = ID2SYM(rb_intern("unblock"));
  SYM_schedule            = ID2SYM(rb_intern("schedule"));
  SYM_block               = ID2SYM(rb_intern("block"));
  SYM_terminate           = ID2SYM(rb_intern("terminate"));

  rb_global_variable(&SYM_spin);
  rb_global_variable(&SYM_enter_poll);
  rb_global_variable(&SYM_leave_poll);
  rb_global_variable(&SYM_unblock);
  rb_global_variable(&SYM_schedule);
  rb_global_variable(&SYM_block);
  rb_global_variable(&SYM_terminate);
}