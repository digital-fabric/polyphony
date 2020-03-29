#include "gyro.h"

ID ID_fiber_trace;
ID ID_ivar_auto_async;
ID ID_ivar_auto_io;
ID ID_trace_ev_loop_enter;
ID ID_trace_ev_loop_leave;
ID ID_trace_run;
ID ID_trace_runnable;
ID ID_trace_terminate;
ID ID_trace_wait;

VALUE SYM_dead;
VALUE SYM_running;
VALUE SYM_runnable;
VALUE SYM_waiting;

VALUE SYM_fiber_create;
VALUE SYM_fiber_ev_loop_enter;
VALUE SYM_fiber_ev_loop_leave;
VALUE SYM_fiber_run;
VALUE SYM_fiber_schedule;
VALUE SYM_fiber_switchpoint;
VALUE SYM_fiber_terminate;

static VALUE Fiber_safe_transfer(int argc, VALUE *argv, VALUE self) {
  VALUE arg = (argc == 0) ? Qnil : argv[0];
  VALUE ret = rb_funcall(self, ID_transfer, 1, arg);

  // fiber is resumed, check if resumed value is an exception
  return RTEST(rb_obj_is_kind_of(ret, rb_eException)) ? 
    rb_funcall(rb_mKernel, ID_raise, 1, ret) : ret;
}

inline VALUE Fiber_auto_async(VALUE self) {
  VALUE async = rb_ivar_get(self, ID_ivar_auto_async);
  if (async == Qnil) {
    async = rb_funcall(cGyro_Async, ID_new, 0);
    rb_ivar_set(self, ID_ivar_auto_async, async);
  }
  return async;
}

inline VALUE Fiber_auto_io(VALUE self) {
  VALUE io = rb_ivar_get(self, ID_ivar_auto_io);
  if (io == Qnil) {
    io = rb_funcall(cGyro_IO, ID_new, 2, Qnil, Qnil);
    rb_ivar_set(self, ID_ivar_auto_io, io);
  }
  return io;
}

static VALUE Fiber_schedule(int argc, VALUE *argv, VALUE self) {
  VALUE value = (argc == 0) ? Qnil : argv[0];
  Fiber_make_runnable(self, value);
  return self;
}

static VALUE Fiber_state(VALUE self) {
  if (!rb_fiber_alive_p(self) || (rb_ivar_get(self, ID_ivar_running) == Qfalse))
    return SYM_dead;
  if (rb_fiber_current() == self) return SYM_running;
  if (rb_ivar_get(self, ID_runnable) != Qnil) return SYM_runnable;
  
  return SYM_waiting;
}

void Fiber_make_runnable(VALUE fiber, VALUE value) {
  VALUE thread = rb_ivar_get(fiber, ID_ivar_thread);
  if (thread != Qnil) {
    Thread_schedule_fiber(thread, fiber, value);
  }
  else {
    rb_warn("No thread set for fiber");
  }
}

void Init_Fiber() {
  VALUE cFiber = rb_const_get(rb_cObject, rb_intern("Fiber"));
  rb_define_method(cFiber, "auto_async", Fiber_auto_async, 0);
  rb_define_method(cFiber, "safe_transfer", Fiber_safe_transfer, -1);
  rb_define_method(cFiber, "schedule", Fiber_schedule, -1);
  rb_define_method(cFiber, "state", Fiber_state, 0);

  ID_ivar_auto_async = rb_intern("@auto_async");

  SYM_dead = ID2SYM(rb_intern("dead"));
  SYM_running = ID2SYM(rb_intern("running"));
  SYM_runnable = ID2SYM(rb_intern("runnable"));
  SYM_waiting = ID2SYM(rb_intern("waiting"));
  rb_global_variable(&SYM_dead);
  rb_global_variable(&SYM_running);
  rb_global_variable(&SYM_runnable);
  rb_global_variable(&SYM_waiting);

  ID_fiber_trace          = rb_intern("__fiber_trace__");

  SYM_fiber_create        = ID2SYM(rb_intern("fiber_create"));
  SYM_fiber_ev_loop_enter = ID2SYM(rb_intern("fiber_ev_loop_enter"));
  SYM_fiber_ev_loop_leave = ID2SYM(rb_intern("fiber_ev_loop_leave"));
  SYM_fiber_run           = ID2SYM(rb_intern("fiber_run"));
  SYM_fiber_schedule      = ID2SYM(rb_intern("fiber_schedule"));
  SYM_fiber_switchpoint   = ID2SYM(rb_intern("fiber_switchpoint"));
  SYM_fiber_terminate     = ID2SYM(rb_intern("fiber_terminate"));

  rb_global_variable(&SYM_fiber_create);
  rb_global_variable(&SYM_fiber_ev_loop_enter);
  rb_global_variable(&SYM_fiber_ev_loop_leave);
  rb_global_variable(&SYM_fiber_run);
  rb_global_variable(&SYM_fiber_schedule);
  rb_global_variable(&SYM_fiber_switchpoint);
  rb_global_variable(&SYM_fiber_terminate);
}