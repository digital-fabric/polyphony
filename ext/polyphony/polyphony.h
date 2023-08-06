#ifndef POLYPHONY_H
#define POLYPHONY_H

#include "ruby.h"
#include "runqueue_ring_buffer.h"
#include "backend_common.h"
#include "buffers.h"

// debugging
#define OBJ_ID(obj) (NUM2LONG(rb_funcall(obj, rb_intern("object_id"), 0)))
#define INSPECT(str, obj) { printf(str); VALUE s = rb_funcall(obj, rb_intern("inspect"), 0); printf(": %s\n", StringValueCStr(s)); }
#define CALLER() rb_funcall(rb_mKernel, rb_intern("caller"), 0)
#define TRACE_CALLER() INSPECT("caller: ", CALLER())
#define TRACE_FREE(ptr) //printf("Free %p %s:%d\n", ptr, __FILE__, __LINE__)

// exceptions
#define TEST_EXCEPTION(ret) (rb_obj_is_kind_of(ret, rb_eException) == Qtrue)
#define RAISE_EXCEPTION(e) rb_funcall(e, ID_invoke, 0);
#define IS_EXCEPTION(o) (rb_obj_is_kind_of(o, rb_eException) == Qtrue)
#define RAISE_IF_EXCEPTION(o) if (IS_EXCEPTION(o)) { RAISE_EXCEPTION(o); }
#define RAISE_IF_NOT_NIL(o) if (o != Qnil) { RAISE_EXCEPTION(o); }

// Fiber#transfer
#if HAVE_RB_FIBER_TRANSFER
  #define FIBER_TRANSFER(fiber, value) rb_fiber_transfer(fiber, 1, &value)
#else
  #define FIBER_TRANSFER(fiber, value) rb_funcall(fiber, ID_transfer, 1, value)
#endif

#define BACKEND() Backend_for_current_thread()

// SAFE is used to cast functions used in rb_ensure
#define SAFE(f) (VALUE (*)(VALUE))(f)

extern VALUE mPolyphony;
extern VALUE cPipe;
extern VALUE cQueue;
extern VALUE cEvent;
extern VALUE cIOStream;
extern VALUE cTimeoutException;

extern ID ID_call;
extern ID ID_caller;
extern ID ID_clear;
extern ID ID_each;
extern ID ID_inspect;
extern ID ID_invoke;
extern ID ID_ivar_backend;
extern ID ID_ivar_blocking_mode;
extern ID ID_ivar_io;
extern ID ID_ivar_multishot_accept_queue;
extern ID ID_ivar_parked;
extern ID ID_ivar_result;
extern ID ID_ivar_runnable;
extern ID ID_ivar_running;
extern ID ID_ivar_thread;
extern ID ID_new;
extern ID ID_raise;
extern ID ID_signal;
extern ID ID_size;
extern ID ID_switch_fiber;
extern ID ID_to_s;
extern ID ID_transfer;

extern VALUE SYM_spin;
extern VALUE SYM_enter_poll;
extern VALUE SYM_leave_poll;
extern VALUE SYM_unblock;
extern VALUE SYM_schedule;
extern VALUE SYM_block;
extern VALUE SYM_terminate;

VALUE Fiber_auto_watcher(VALUE self);
void Fiber_make_runnable(VALUE fiber, VALUE value);

VALUE Queue_push(VALUE self, VALUE value);
VALUE Queue_unshift(VALUE self, VALUE value);
VALUE Queue_shift(int argc,VALUE *argv, VALUE self);
VALUE Queue_shift_all(VALUE self);

void Runqueue_push(VALUE self, VALUE fiber, VALUE value, int reschedule);
void Runqueue_unshift(VALUE self, VALUE fiber, VALUE value, int reschedule);
runqueue_entry Runqueue_shift(VALUE self);
void Runqueue_delete(VALUE self, VALUE fiber);
int Runqueue_index_of(VALUE self, VALUE fiber);
void Runqueue_clear(VALUE self);
long Runqueue_len(VALUE self);
int Runqueue_empty_p(VALUE self);
int Runqueue_should_poll_nonblocking(VALUE self);

void Pipe_verify_blocking_mode(VALUE self, VALUE blocking);
int Pipe_get_fd(VALUE self, int write_mode);
VALUE Pipe_close(VALUE self);

#ifdef POLYPHONY_BACKEND_LIBEV
#define Backend_recv_loop Backend_read_loop
#define Backend_recv_feed_loop Backend_feed_loop
#endif

// Backend public interface

VALUE Backend_for_current_thread();

VALUE Backend_accept(VALUE self, VALUE server_socket, VALUE socket_class);
VALUE Backend_accept_loop(VALUE self, VALUE server_socket, VALUE socket_class);
VALUE Backend_connect(VALUE self, VALUE io, VALUE addr, VALUE port);
VALUE Backend_feed_loop(VALUE self, VALUE io, VALUE receiver, VALUE method);
VALUE Backend_read(VALUE self, VALUE io, VALUE str, VALUE length, VALUE to_eof, VALUE pos);
VALUE Backend_read_loop(VALUE self, VALUE io, VALUE maxlen);
VALUE Backend_recv(VALUE self, VALUE io, VALUE str, VALUE length, VALUE pos);
VALUE Backend_recvmsg(VALUE self, VALUE io, VALUE buffer, VALUE maxlen, VALUE pos, VALUE flags, VALUE maxcontrollen, VALUE opts);
VALUE Backend_recv_loop(VALUE self, VALUE io, VALUE maxlen);
VALUE Backend_recv_feed_loop(VALUE self, VALUE io, VALUE receiver, VALUE method);
VALUE Backend_send(VALUE self, VALUE io, VALUE msg, VALUE flags);
VALUE Backend_sendmsg(VALUE self, VALUE io, VALUE msg, VALUE flags, VALUE dest_sockaddr, VALUE controls);
VALUE Backend_sendv(VALUE self, VALUE io, VALUE ary, VALUE flags);
VALUE Backend_sleep(VALUE self, VALUE duration);
VALUE Backend_splice(VALUE self, VALUE src, VALUE dest, VALUE maxlen);

#ifdef POLYPHONY_BACKEND_LIBURING
VALUE Backend_double_splice(VALUE self, VALUE src, VALUE dest);
#endif

#ifdef POLYPHONY_LINUX
VALUE Backend_tee(VALUE self, VALUE src, VALUE dest, VALUE maxlen);
#endif

VALUE Backend_timeout(int argc,VALUE *argv, VALUE self);
VALUE Backend_timer_loop(VALUE self, VALUE interval);
VALUE Backend_wait_event(VALUE self, VALUE raise);
VALUE Backend_wait_io(VALUE self, VALUE io, VALUE write);
VALUE Backend_waitpid(VALUE self, VALUE pid);
VALUE Backend_write(VALUE self, VALUE io, VALUE str);
VALUE Backend_write_m(int argc, VALUE *argv, VALUE self);
VALUE Backend_close(VALUE self, VALUE io);

VALUE Backend_poll(VALUE self, VALUE blocking);
VALUE Backend_wait_event(VALUE self, VALUE raise_on_exception);
VALUE Backend_wakeup(VALUE self);
VALUE Backend_run_idle_tasks(VALUE self);
VALUE Backend_switch_fiber(VALUE self);

void Backend_schedule_fiber(VALUE thread, VALUE self, VALUE fiber, VALUE value, int prioritize);
void Backend_unschedule_fiber(VALUE self, VALUE fiber);
void Backend_park_fiber(VALUE self, VALUE fiber);
void Backend_unpark_fiber(VALUE self, VALUE fiber);

VALUE Backend_snooze(VALUE self);
VALUE Backend_stream_read(VALUE self, VALUE io, buffer_descriptor *desc, int len, int *result);

void Thread_schedule_fiber(VALUE thread, VALUE fiber, VALUE value);
void Thread_schedule_fiber_with_priority(VALUE thread, VALUE fiber, VALUE value);
VALUE Thread_switch_fiber(VALUE thread);

VALUE Event_signal(int argc, VALUE *argv, VALUE event);
VALUE Event_await(VALUE event);

VALUE Polyphony_snooze(VALUE self);

// IOStream reading API
VALUE Polyphony_stream_read(VALUE io, buffer_descriptor *desc, int len, int *result);

#endif /* POLYPHONY_H */
