#include "gyro.h"

struct Gyro_Selector {
  struct  ev_loop *ev_loop;
  long    run_no_wait_count;
  int     ev_loop_running;
  struct  ev_async async;
};

VALUE cGyro_Selector = Qnil;

static void Gyro_Selector_mark(void *ptr) {
  // struct Gyro_Selector *selector = ptr;
}

static void Gyro_Selector_free(void *ptr) {
  struct Gyro_Selector *selector = ptr;
  ev_async_stop(selector->ev_loop, &selector->async);
  if (selector->ev_loop && !ev_is_default_loop(selector->ev_loop)) {
    // printf("Selector garbage collected before being stopped!\n");
    ev_loop_destroy(selector->ev_loop);
  }
  xfree(selector);
}

static size_t Gyro_Selector_size(const void *ptr) {
  return sizeof(struct Gyro_Selector);
}

static const rb_data_type_t Gyro_Selector_type = {
    "Gyro_Selector",
    {Gyro_Selector_mark, Gyro_Selector_free, Gyro_Selector_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE Gyro_Selector_allocate(VALUE klass) {
  struct Gyro_Selector *selector = (struct Gyro_Selector *)xmalloc(sizeof(struct Gyro_Selector));
  return TypedData_Wrap_Struct(klass, &Gyro_Selector_type, selector);
}

#define GetGyro_Selector(obj, selector) \
  TypedData_Get_Struct((obj), struct Gyro_Selector, &Gyro_Selector_type, (selector))

inline struct ev_loop *Gyro_Selector_ev_loop(VALUE self) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);

  return selector->ev_loop;
}

inline struct ev_loop *Gyro_Selector_current_thread_ev_loop() {
  struct Gyro_Selector *selector;
  GetGyro_Selector(Thread_current_event_selector(), selector);

  return selector->ev_loop;
}

inline ev_tstamp Gyro_Selector_now(VALUE self) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);

  return ev_now(selector->ev_loop);
}

long Gyro_Selector_pending_count(VALUE self) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);

  return ev_pending_count(selector->ev_loop);
}

void dummy_async_callback(struct ev_loop *ev_loop, struct ev_async *ev_async, int revents) {
  // This callback does nothing, the selector's async is used solely for waking
  // up the event loop.
}

static VALUE Gyro_Selector_initialize(VALUE self, VALUE thread) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);

  int use_default_loop = (rb_thread_current() == rb_thread_main());
  selector->ev_loop = use_default_loop ? EV_DEFAULT : ev_loop_new(EVFLAG_NOSIGMASK);
  selector->run_no_wait_count = 0;

  ev_async_init(&selector->async, dummy_async_callback);
  ev_async_start(selector->ev_loop, &selector->async);
  ev_run(selector->ev_loop, EVRUN_NOWAIT);
  return Qnil;
}

inline VALUE Gyro_Selector_run(VALUE self, VALUE current_fiber) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);
  if (selector->ev_loop) {
    selector->run_no_wait_count = 0;
    FIBER_TRACE(2, SYM_fiber_ev_loop_enter, current_fiber);
    selector->ev_loop_running = 1;
    ev_run(selector->ev_loop, EVRUN_ONCE);
    selector->ev_loop_running = 0;
    FIBER_TRACE(2, SYM_fiber_ev_loop_leave, current_fiber);
  }
  return Qnil;
}

inline void Gyro_Selector_run_no_wait(VALUE self, VALUE current_fiber, long runnable_count) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);

  selector->run_no_wait_count++;
  if (selector->run_no_wait_count < runnable_count || selector->run_no_wait_count < 10) {
    return;
  }

  selector->run_no_wait_count = 0;
  FIBER_TRACE(2, SYM_fiber_ev_loop_enter, current_fiber);
  ev_run(selector->ev_loop, EVRUN_NOWAIT);
  FIBER_TRACE(2, SYM_fiber_ev_loop_leave, current_fiber);
}

VALUE Gyro_Selector_stop(VALUE self) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);

  if (selector->ev_loop && !ev_is_default_loop(selector->ev_loop)) {
    // ev_loop_destroy(selector->ev_loop);
    // selector->ev_loop = 0;
  }
  return Qnil;
}

VALUE Gyro_Selector_break_out_of_ev_loop(VALUE self) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);

  if (selector->ev_loop_running) {
    // Since the loop will run until at least one event has occurred, we signal
    // the selector's associated async watcher, which will cause the ev loop to
    // return. In contrast to using `ev_break` to break out of the loop, which
    // should be called from the same thread (from within the ev_loop), using an
    // `ev_async` allows us to interrupt the event loop across threads.
    ev_async_send(selector->ev_loop, &selector->async);
    return Qtrue;
  }

  return Qnil;
}

inline static VALUE Gyro_Selector_wait_readable(VALUE self, VALUE io) {
  VALUE watcher = IO_read_watcher(io);
  return Gyro_IO_await(watcher);
}

inline static VALUE Gyro_Selector_wait_writable(VALUE self, VALUE io) {
  VALUE watcher = IO_write_watcher(io);
  return Gyro_IO_await(watcher);
}

inline static VALUE Gyro_Selector_wait_timeout(VALUE self, VALUE duration) {
  VALUE watcher = rb_funcall(cGyro_Timer, ID_new, 2, duration, Qnil);
  return Gyro_Timer_await(watcher);
}

void Init_Gyro_Selector() {
  cGyro_Selector = rb_define_class_under(mGyro, "Selector", rb_cData);
  rb_define_alloc_func(cGyro_Selector, Gyro_Selector_allocate);

  rb_define_method(cGyro_Selector, "initialize", Gyro_Selector_initialize, 1);
  rb_define_method(cGyro_Selector, "run", Gyro_Selector_run, 1);
  rb_define_method(cGyro_Selector, "stop", Gyro_Selector_stop, 0);
  rb_define_method(cGyro_Selector, "wait_readable", Gyro_Selector_wait_readable, 1);
  rb_define_method(cGyro_Selector, "wait_writable", Gyro_Selector_wait_writable, 1);
  rb_define_method(cGyro_Selector, "wait_timeout", Gyro_Selector_wait_timeout, 1);
  rb_define_method(cGyro_Selector, "break_out_of_ev_loop", Gyro_Selector_break_out_of_ev_loop, 0);
}
