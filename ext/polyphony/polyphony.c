#include "polyphony.h"

VALUE mPolyphony;
VALUE cTimeoutException;

ID ID_call;
ID ID_caller;
ID ID_clear;
ID ID_each;
ID ID_inspect;
ID ID_invoke;
ID ID_new;
ID ID_ivar_blocking_mode;
ID ID_ivar_io;
ID ID_ivar_runnable;
ID ID_ivar_running;
ID ID_ivar_thread;
ID ID_size;
ID ID_signal;
ID ID_switch_fiber;
ID ID_transfer;
ID ID_R;
ID ID_W;
ID ID_RW;

VALUE Polyphony_snooze(VALUE self) {
  VALUE ret;
  VALUE fiber = rb_fiber_current();

  Fiber_make_runnable(fiber, Qnil);
  ret = Thread_switch_fiber(rb_thread_current());
  RAISE_IF_EXCEPTION(ret);
  RB_GC_GUARD(ret);
  return ret;
}

static VALUE Polyphony_suspend(VALUE self) {
  VALUE ret = Thread_switch_fiber(rb_thread_current());

  RAISE_IF_EXCEPTION(ret);
  RB_GC_GUARD(ret);
  return ret;
}

VALUE Polyphony_backend_accept(VALUE self, VALUE server_socket, VALUE socket_class) {
  return Backend_accept(BACKEND(), server_socket, socket_class);
}

VALUE Polyphony_backend_accept_loop(VALUE self, VALUE server_socket, VALUE socket_class) {
  return Backend_accept_loop(BACKEND(), server_socket, socket_class);
}

VALUE Polyphony_backend_connect(VALUE self, VALUE io, VALUE addr, VALUE port) {
  return Backend_connect(BACKEND(), io, addr, port);
}

VALUE Polyphony_backend_feed_loop(VALUE self, VALUE io, VALUE receiver, VALUE method) {
  return Backend_feed_loop(BACKEND(), io, receiver, method);
}

VALUE Polyphony_backend_read(VALUE self, VALUE io, VALUE str, VALUE length, VALUE to_eof) {
  return Backend_read(BACKEND(), io, str, length, to_eof);
}

VALUE Polyphony_backend_read_loop(VALUE self, VALUE io) {
  return Backend_read_loop(BACKEND(), io);
}

VALUE Polyphony_backend_recv(VALUE self, VALUE io, VALUE str, VALUE length) {
  return Backend_recv(BACKEND(), io, str, length);
}

VALUE Polyphony_backend_recv_loop(VALUE self, VALUE io) {
  return Backend_recv_loop(BACKEND(), io);
}

VALUE Polyphony_backend_recv_feed_loop(VALUE self, VALUE io, VALUE receiver, VALUE method) {
  return Backend_recv_feed_loop(BACKEND(), io, receiver, method);
}

VALUE Polyphony_backend_send(VALUE self, VALUE io, VALUE msg, VALUE flags) {
  return Backend_send(BACKEND(), io, msg, flags);
}

VALUE Polyphony_backend_sendv(VALUE self, VALUE io, VALUE ary, VALUE flags) {
  return Backend_sendv(BACKEND(), io, ary, flags);
}

VALUE Polyphony_backend_sleep(VALUE self, VALUE duration) {
  return Backend_sleep(BACKEND(), duration);
}

VALUE Polyphony_backend_splice(VALUE self, VALUE src, VALUE dest, VALUE maxlen) {
  return Backend_splice(BACKEND(), src, dest, maxlen);
}

VALUE Polyphony_backend_splice_to_eof(VALUE self, VALUE src, VALUE dest, VALUE chunksize) {
  return Backend_splice_to_eof(BACKEND(), src, dest, chunksize);
}

VALUE Polyphony_backend_timeout(int argc,VALUE *argv, VALUE self) {
  return Backend_timeout(argc, argv, BACKEND());
}

VALUE Polyphony_backend_timer_loop(VALUE self, VALUE interval) {
  return Backend_timer_loop(BACKEND(), interval);
}

VALUE Polyphony_backend_wait_event(VALUE self, VALUE raise) {
  return Backend_wait_event(BACKEND(), raise);
}

VALUE Polyphony_backend_wait_io(VALUE self, VALUE io, VALUE write) {
  return Backend_wait_io(BACKEND(), io, write);
}

VALUE Polyphony_backend_waitpid(VALUE self, VALUE pid) {
  return Backend_waitpid(BACKEND(), pid);
}

VALUE Polyphony_backend_write(int argc, VALUE *argv, VALUE self) {
  return Backend_write_m(argc, argv, BACKEND());
}

void Init_Polyphony() {
  mPolyphony = rb_define_module("Polyphony");

  // backend methods
  rb_define_singleton_method(mPolyphony, "backend_accept", Polyphony_backend_accept, 2);
  rb_define_singleton_method(mPolyphony, "backend_accept_loop", Polyphony_backend_accept_loop, 2);
  rb_define_singleton_method(mPolyphony, "backend_connect", Polyphony_backend_connect, 3);
  rb_define_singleton_method(mPolyphony, "backend_feed_loop", Polyphony_backend_feed_loop, 3);
  rb_define_singleton_method(mPolyphony, "backend_read", Polyphony_backend_read, 4);
  rb_define_singleton_method(mPolyphony, "backend_read_loop", Polyphony_backend_read_loop, 1);
  rb_define_singleton_method(mPolyphony, "backend_recv", Polyphony_backend_recv, 3);
  rb_define_singleton_method(mPolyphony, "backend_recv_loop", Polyphony_backend_recv_loop, 1);
  rb_define_singleton_method(mPolyphony, "backend_recv_feed_loop", Polyphony_backend_recv_feed_loop, 3);
  rb_define_singleton_method(mPolyphony, "backend_send", Polyphony_backend_send, 3);
  rb_define_singleton_method(mPolyphony, "backend_sendv", Polyphony_backend_sendv, 3);
  rb_define_singleton_method(mPolyphony, "backend_sleep", Polyphony_backend_sleep, 1);
  rb_define_singleton_method(mPolyphony, "backend_splice", Polyphony_backend_splice, 3);
  rb_define_singleton_method(mPolyphony, "backend_splice_to_eof", Polyphony_backend_splice_to_eof, 3);
  rb_define_singleton_method(mPolyphony, "backend_timeout", Polyphony_backend_timeout, -1);
  rb_define_singleton_method(mPolyphony, "backend_timer_loop", Polyphony_backend_timer_loop, 1);
  rb_define_singleton_method(mPolyphony, "backend_wait_event", Polyphony_backend_wait_event, 1);
  rb_define_singleton_method(mPolyphony, "backend_wait_io", Polyphony_backend_wait_io, 2);
  rb_define_singleton_method(mPolyphony, "backend_waitpid", Polyphony_backend_waitpid, 1);
  rb_define_singleton_method(mPolyphony, "backend_write", Polyphony_backend_write, -1);

  rb_define_global_function("snooze", Polyphony_snooze, 0);
  rb_define_global_function("suspend", Polyphony_suspend, 0);

  cTimeoutException = rb_define_class_under(mPolyphony, "TimeoutException", rb_eException);

  ID_call               = rb_intern("call");
  ID_caller             = rb_intern("caller");
  ID_clear              = rb_intern("clear");
  ID_each               = rb_intern("each");
  ID_inspect            = rb_intern("inspect");
  ID_invoke             = rb_intern("invoke");
  ID_ivar_blocking_mode = rb_intern("@blocking_mode");
  ID_ivar_io            = rb_intern("@io");
  ID_ivar_runnable      = rb_intern("@runnable");
  ID_ivar_running       = rb_intern("@running");
  ID_ivar_thread        = rb_intern("@thread");
  ID_new                = rb_intern("new");
  ID_signal             = rb_intern("signal");
  ID_size               = rb_intern("size");
  ID_switch_fiber       = rb_intern("switch_fiber");
  ID_transfer           = rb_intern("transfer");
}