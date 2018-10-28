#include "ev.h"

struct EV_Timer {
  struct  ev_timer ev_timer;
  int     active;
  double  after;
  double  repeat;
  VALUE   self;
  VALUE   callback;
  VALUE   fiber;
};

static VALUE mEV = Qnil;
static VALUE cEV_Timer = Qnil;

/* Allocator/deallocator */
static VALUE EV_Timer_allocate(VALUE klass);
static void EV_Timer_mark(struct EV_Timer *timer);
static void EV_Timer_free(struct EV_Timer *timer);
static size_t EV_Timer_size(struct EV_Timer *timer);

/* Methods */
static VALUE EV_Timer_initialize(VALUE self, VALUE after, VALUE repeat);

static VALUE EV_Timer_start(VALUE self);
static VALUE EV_Timer_stop(VALUE self);
static VALUE EV_Timer_reset(VALUE self);
static VALUE EV_Timer_await(VALUE self);

void EV_Timer_callback(ev_loop *ev_loop, struct ev_timer *timer, int revents);

static ID ID_call = Qnil;

/* Timer encapsulates an timer watcher */
void Init_EV_Timer() {
  mEV = rb_define_module("EV");
  cEV_Timer = rb_define_class_under(mEV, "Timer", rb_cData);
  rb_define_alloc_func(cEV_Timer, EV_Timer_allocate);

  rb_define_method(cEV_Timer, "initialize", EV_Timer_initialize, 2);
  rb_define_method(cEV_Timer, "start", EV_Timer_start, 0);
  rb_define_method(cEV_Timer, "stop", EV_Timer_stop, 0);
  rb_define_method(cEV_Timer, "reset", EV_Timer_reset, 0);
  rb_define_method(cEV_Timer, "await", EV_Timer_await, 0);
  

  ID_call = rb_intern("call");
}

static const rb_data_type_t EV_Timer_type = {
    "EV_Timer",
    {EV_Timer_mark, EV_Timer_free, EV_Timer_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE EV_Timer_allocate(VALUE klass) {
  struct EV_Timer *timer = (struct EV_Timer *)xmalloc(sizeof(struct EV_Timer));
  return TypedData_Wrap_Struct(klass, &EV_Timer_type, timer);
}

static void EV_Timer_mark(struct EV_Timer *timer) {
  if (timer->callback != Qnil) {
    rb_gc_mark(timer->callback);
  }
  if (timer->fiber != Qnil) {
    rb_gc_mark(timer->fiber);
  }
}

static void EV_Timer_free(struct EV_Timer *timer) {
  if (timer->active) {
    ev_timer_stop(EV_DEFAULT, &timer->ev_timer);
  }
  xfree(timer);
}

static size_t EV_Timer_size(struct EV_Timer *timer) {
  return sizeof(struct EV_Timer);
}

#define GetEV_Timer(obj, timer) \
  TypedData_Get_Struct((obj), struct EV_Timer, &EV_Timer_type, (timer))

static VALUE EV_Timer_initialize(VALUE self, VALUE after, VALUE repeat) {
  struct EV_Timer *timer;

  GetEV_Timer(self, timer);

  timer->self     = self;
  timer->callback = Qnil;
  timer->fiber    = Qnil;
  timer->after    = NUM2DBL(after);
  timer->repeat   = NUM2DBL(repeat);
  timer->active   = 0;
  
  ev_timer_init(&timer->ev_timer, EV_Timer_callback, timer->after, timer->repeat);

  return Qnil;
}

void EV_Timer_callback(ev_loop *ev_loop, struct ev_timer *ev_timer, int revents) {
  VALUE fiber;
  struct EV_Timer *timer = (struct EV_Timer*)ev_timer;

  if (!timer->repeat) {
    timer->active = 0;
    EV_del_watcher_ref(timer->self);
  }

  if (timer->fiber != Qnil) {
    ev_timer_stop(EV_DEFAULT, ev_timer);
    EV_del_watcher_ref(timer->self);
    timer->active = 0;
    fiber = timer->fiber;
    timer->fiber = Qnil;
    rb_fiber_resume(fiber, 0, 0);
  }
  else if (timer->callback != Qnil) {
    rb_funcall(timer->callback, ID_call, 1, Qtrue);
  }
}

static VALUE EV_Timer_start(VALUE self) {
  struct EV_Timer *timer;
  GetEV_Timer(self, timer);

  if (rb_block_given_p()) {
    timer->callback = rb_block_proc();
  }

  if (!timer->active) {
    ev_timer_start(EV_DEFAULT, &timer->ev_timer);
    timer->active = 1;
    EV_add_watcher_ref(self);
  }

  return self;
}

static VALUE EV_Timer_stop(VALUE self) {
  struct EV_Timer *timer;
  GetEV_Timer(self, timer);

  if (timer->active) {
    ev_timer_stop(EV_DEFAULT, &timer->ev_timer);
    timer->active = 0;
    EV_del_watcher_ref(self);
  }

  return self;
}

static VALUE EV_Timer_reset(VALUE self) {
  struct EV_Timer *timer;
  int prev_active;
  GetEV_Timer(self, timer);

  prev_active = timer->active;

  if (prev_active) {
    ev_timer_stop(EV_DEFAULT, &timer->ev_timer);
  }
  ev_timer_set(&timer->ev_timer, timer->after, timer->repeat);
  ev_timer_start(EV_DEFAULT, &timer->ev_timer);
  if (!prev_active) {
    timer->active = 1;
    EV_add_watcher_ref(self);
  }

  return self;
}

static VALUE EV_Timer_await(VALUE self) {
  struct EV_Timer *timer;
  VALUE ret;
  
  GetEV_Timer(self, timer);

  timer->fiber = rb_fiber_current();
  timer->active = 1;
  ev_timer_start(EV_DEFAULT, &timer->ev_timer);
  EV_add_watcher_ref(self);

  ret = rb_fiber_yield(0, 0);

  // fiber is resumed
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    return rb_funcall(ret, rb_intern("raise"), 1, ret);
  }
  else {
    return Qnil;
  }
}