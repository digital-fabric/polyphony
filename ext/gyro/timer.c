#include "gyro.h"

struct Gyro_Timer {
  struct  ev_timer ev_timer;
  struct  ev_loop *ev_loop;
  int     active;
  double  after;
  double  repeat;
  VALUE   self;
  VALUE   fiber;
  VALUE   selector;
};

VALUE cGyro_Timer = Qnil;

static void Gyro_Timer_mark(void *ptr) {
  struct Gyro_Timer *timer = ptr;
  if (timer->fiber != Qnil) {
    rb_gc_mark(timer->fiber);
  }
  if (timer->selector != Qnil) {
    rb_gc_mark(timer->selector);
  }
}

static void Gyro_Timer_free(void *ptr) {
  struct Gyro_Timer *timer = ptr;
  if (timer->active) {
    ev_clear_pending(timer->ev_loop, &timer->ev_timer);
    ev_timer_stop(timer->ev_loop, &timer->ev_timer);
  }
  xfree(timer);
}

static size_t Gyro_Timer_size(const void *ptr) {
  return sizeof(struct Gyro_Timer);
}

static const rb_data_type_t Gyro_Timer_type = {
    "Gyro_Timer",
    {Gyro_Timer_mark, Gyro_Timer_free, Gyro_Timer_size,},
    0, 0, 0
};

static VALUE Gyro_Timer_allocate(VALUE klass) {
  struct Gyro_Timer *timer = ALLOC(struct Gyro_Timer);
  return TypedData_Wrap_Struct(klass, &Gyro_Timer_type, timer);
}

#define GetGyro_Timer(obj, timer) \
  TypedData_Get_Struct((obj), struct Gyro_Timer, &Gyro_Timer_type, (timer))

void Gyro_Timer_callback(struct ev_loop *ev_loop, struct ev_timer *ev_timer, int revents) {
  struct Gyro_Timer *timer = (struct Gyro_Timer*)ev_timer;

  if (!timer->repeat) {
    Gyro_Selector_remove_active_watcher(timer->selector, timer->self);
    timer->active = 0;
    timer->selector = Qnil;
  }

  if (timer->fiber != Qnil) {
    Gyro_schedule_fiber(timer->fiber, DBL2NUM(timer->after));
  }
}

static VALUE Gyro_Timer_initialize(VALUE self, VALUE after, VALUE repeat) {
  struct Gyro_Timer *timer;

  GetGyro_Timer(self, timer);

  timer->self     = self;
  timer->fiber    = Qnil;
  timer->after    = NUM2DBL(after);
  timer->repeat   = NUM2DBL(repeat);
  timer->active   = 0;
  timer->ev_loop  = 0;
  timer->selector = Qnil;

  ev_timer_init(&timer->ev_timer, Gyro_Timer_callback, timer->after, timer->repeat);

  return Qnil;
}

VALUE Gyro_Timer_stop(VALUE self) {
  struct Gyro_Timer *timer;
  GetGyro_Timer(self, timer);

  if (timer->active) {
    if (timer->selector != Qnil)
      Gyro_Selector_remove_active_watcher(timer->selector, self);
    ev_timer_stop(timer->ev_loop, &timer->ev_timer);
    timer->active = 0;
    timer->fiber = Qnil;
    timer->selector = Qnil;
    timer->ev_loop = 0;
  }

  return self;
}

VALUE Gyro_Timer_await(VALUE self) {
  struct Gyro_Timer *timer;
  VALUE ret;
  
  GetGyro_Timer(self, timer);

  timer->fiber = rb_fiber_current();
  timer->selector = Thread_current_event_selector();
  timer->ev_loop = Gyro_Selector_ev_loop(timer->selector);

  if (!timer->active) {
    timer->active = 1;
    ev_timer_start(timer->ev_loop, &timer->ev_timer);
    Gyro_Selector_add_active_watcher(timer->selector, self);
  }

  ret = Fiber_await();

  if (timer->active && (timer->repeat == .0)) {
    Gyro_Selector_remove_active_watcher(timer->selector, self);
    ev_timer_stop(timer->ev_loop, &timer->ev_timer);
    timer->active = 0;
    timer->ev_loop = 0;
  }

  // fiber is resumed, check if resumed value is an exception
  timer->fiber = Qnil;
  timer->selector = Qnil;

  RB_GC_GUARD(ret);
  RB_GC_GUARD(self);
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    return rb_funcall(rb_mKernel, ID_raise, 1, ret);
  }
  else
    return ret;
}

void Init_Gyro_Timer() {
  cGyro_Timer = rb_define_class_under(mGyro, "Timer", rb_cData);
  rb_define_alloc_func(cGyro_Timer, Gyro_Timer_allocate);

  rb_define_method(cGyro_Timer, "initialize", Gyro_Timer_initialize, 2);
  rb_define_method(cGyro_Timer, "stop", Gyro_Timer_stop, 0);
  rb_define_method(cGyro_Timer, "await", Gyro_Timer_await, 0);
}
