#include "gyro.h"

struct Gyro_Timer {
  struct  ev_timer ev_timer;
  int     active;
  double  after;
  double  repeat;
  VALUE   self;
  VALUE   fiber;
};

static VALUE cGyro_Timer = Qnil;

/* Allocator/deallocator */
static VALUE Gyro_Timer_allocate(VALUE klass);
static void Gyro_Timer_mark(void *ptr);
static void Gyro_Timer_free(void *ptr);
static size_t Gyro_Timer_size(const void *ptr);

/* Methods */
static VALUE Gyro_Timer_initialize(VALUE self, VALUE after, VALUE repeat);

static VALUE Gyro_Timer_await(VALUE self);

void Gyro_Timer_callback(struct ev_loop *ev_loop, struct ev_timer *timer, int revents);

/* Timer encapsulates an timer watcher */
void Init_Gyro_Timer() {
  cGyro_Timer = rb_define_class_under(mGyro, "Timer", rb_cData);
  rb_define_alloc_func(cGyro_Timer, Gyro_Timer_allocate);

  rb_define_method(cGyro_Timer, "initialize", Gyro_Timer_initialize, 2);
  rb_define_method(cGyro_Timer, "await", Gyro_Timer_await, 0);
}

static const rb_data_type_t Gyro_Timer_type = {
    "Gyro_Timer",
    {Gyro_Timer_mark, Gyro_Timer_free, Gyro_Timer_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE Gyro_Timer_allocate(VALUE klass) {
  struct Gyro_Timer *timer = (struct Gyro_Timer *)xmalloc(sizeof(struct Gyro_Timer));
  return TypedData_Wrap_Struct(klass, &Gyro_Timer_type, timer);
}

static void Gyro_Timer_mark(void *ptr) {
  struct Gyro_Timer *timer = ptr;
  if (timer->fiber != Qnil) {
    rb_gc_mark(timer->fiber);
  }
}

static void Gyro_Timer_free(void *ptr) {
  struct Gyro_Timer *timer = ptr;
  if (timer->active) {
    ev_timer_stop(EV_DEFAULT, &timer->ev_timer);
  }
  xfree(timer);
}

static size_t Gyro_Timer_size(const void *ptr) {
  return sizeof(struct Gyro_Timer);
}

#define GetGyro_Timer(obj, timer) \
  TypedData_Get_Struct((obj), struct Gyro_Timer, &Gyro_Timer_type, (timer))

static VALUE Gyro_Timer_initialize(VALUE self, VALUE after, VALUE repeat) {
  struct Gyro_Timer *timer;

  GetGyro_Timer(self, timer);

  timer->self     = self;
  timer->fiber    = Qnil;
  timer->after    = NUM2DBL(after);
  timer->repeat   = NUM2DBL(repeat);
  timer->active   = 0;
  
  ev_timer_init(&timer->ev_timer, Gyro_Timer_callback, timer->after, timer->repeat);

  return Qnil;
}

void Gyro_Timer_callback(struct ev_loop *ev_loop, struct ev_timer *ev_timer, int revents) {
  struct Gyro_Timer *timer = (struct Gyro_Timer*)ev_timer;

  if (!timer->repeat) {
    timer->active = 0;
  }

  if (timer->fiber != Qnil) {
    VALUE fiber = timer->fiber;
    VALUE resume_value = DBL2NUM(timer->after);

    ev_timer_stop(EV_DEFAULT, ev_timer);
    timer->active = 0;
    timer->fiber = Qnil;
    Gyro_schedule_fiber(fiber, resume_value);
  }
}

static VALUE Gyro_Timer_await(VALUE self) {
  struct Gyro_Timer *timer;
  VALUE ret;
  
  GetGyro_Timer(self, timer);

  timer->fiber = rb_fiber_current();
  timer->active = 1;
  ev_timer_start(EV_DEFAULT, &timer->ev_timer);

  ret = Gyro_yield();

  // fiber is resumed, check if resumed value is an exception
  timer->fiber = Qnil;
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    if (timer->active) {
      timer->active = 0;
      ev_timer_stop(EV_DEFAULT, &timer->ev_timer);
    }
    return rb_funcall(rb_mKernel, ID_raise, 1, ret);
  }
  else
    return ret;
}