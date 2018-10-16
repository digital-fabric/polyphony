#include "ev.h"

struct EV_Timer {
  VALUE   self;
  struct  ev_timer ev_timer;
  int     active;
  int     free_in_callback;
  double  after;
  double  repeat;
  VALUE   callback;
};

static VALUE mEV = Qnil;
static VALUE cEV_Timer = Qnil;

/* Allocator/deallocator */
static VALUE EV_Timer_allocate(VALUE klass);
static void EV_Timer_mark(struct EV_Timer *timer);
static void EV_Timer_free(struct EV_Timer *timer);

/* Methods */
static VALUE EV_Timer_initialize(VALUE self, VALUE after, VALUE repeat);

static VALUE EV_Timer_start(VALUE self);
static VALUE EV_Timer_stop(VALUE self);

void EV_Timer_callback(ev_loop *ev_loop, struct ev_timer *timer, int revents);

/* Timer encapsulates an timer watcher */
void Init_EV_Timer() {
  mEV = rb_define_module("EV");
  cEV_Timer = rb_define_class_under(mEV, "Timer", rb_cObject);
  rb_define_alloc_func(cEV_Timer, EV_Timer_allocate);

  rb_define_method(cEV_Timer, "initialize", EV_Timer_initialize, 2);
  rb_define_method(cEV_Timer, "start", EV_Timer_start, 0);
  rb_define_method(cEV_Timer, "stop", EV_Timer_stop, 0);
}

static VALUE EV_Timer_allocate(VALUE klass) {
  struct EV_Timer *timer = (struct EV_Timer *)xmalloc(sizeof(struct EV_Timer));

  return Data_Wrap_Struct(klass, EV_Timer_mark, EV_Timer_free, timer);
}

static void EV_Timer_mark(struct EV_Timer *timer) {
  if (timer->callback) {
    rb_gc_mark(timer->callback);
  }
}

static void EV_Timer_free(struct EV_Timer *timer) {
  ev_timer_stop(EV_DEFAULT, &timer->ev_timer);

  if ev_is_pending(&timer->ev_timer) {
    timer->free_in_callback = 1;
  }
  else {
    xfree(timer);
  }
}

static VALUE EV_Timer_initialize(VALUE self, VALUE after, VALUE repeat) {
  struct EV_Timer *timer;

  Data_Get_Struct(self, struct EV_Timer, timer);

  timer->self = self;
  timer->callback = rb_block_proc();
  timer->after = NUM2DBL(after);
  timer->repeat = NUM2DBL(repeat);
  
  ev_timer_init(&timer->ev_timer, EV_Timer_callback, timer->after, timer->repeat);
  timer->ev_timer.data = (void *)timer;

  ev_timer_start(EV_DEFAULT, &timer->ev_timer);
  EV_add_watcher_ref(self);
  timer->active = 1;
  timer->free_in_callback = 0;

  return Qnil;
}

/* libev callback fired on IO event */
void EV_Timer_callback(ev_loop *ev_loop, struct ev_timer *ev_timer, int revents) {
  struct EV_Timer *timer = (struct EV_Timer *)ev_timer->data;

  if (timer->free_in_callback) {
    xfree(timer);
    return;
  }

  if (!timer->repeat) {
    EV_del_watcher_ref(timer->self);
    timer->active = 0;
  }
  rb_funcall(timer->callback, rb_intern("call"), 1, Qtrue);
}

static VALUE EV_Timer_start(VALUE self) {
  struct EV_Timer *timer;
  Data_Get_Struct(self, struct EV_Timer, timer);
  if (!timer->active) {
    ev_timer_start(EV_DEFAULT, &timer->ev_timer);
    EV_add_watcher_ref(self);
    timer->active = 1;
  }

  return Qnil;
}

static VALUE EV_Timer_stop(VALUE self) {
  struct EV_Timer *timer;
  Data_Get_Struct(self, struct EV_Timer, timer);

  if (timer->active) {
    ev_timer_stop(EV_DEFAULT, &timer->ev_timer);
    EV_del_watcher_ref(self);
    timer->active = 0;
  }

  return Qnil;
}
