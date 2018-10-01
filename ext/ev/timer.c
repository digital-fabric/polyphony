#include "ev.h"

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
void Init_EV_Timer()
{
  mEV = rb_define_module("EV");
  cEV_Timer = rb_define_class_under(mEV, "Timer", rb_cObject);
  rb_define_alloc_func(cEV_Timer, EV_Timer_allocate);

  rb_define_method(cEV_Timer, "initialize", EV_Timer_initialize, 2);
  rb_define_method(cEV_Timer, "start", EV_Timer_start, 0);
  rb_define_method(cEV_Timer, "stop", EV_Timer_stop, 0);
}

static VALUE EV_Timer_allocate(VALUE klass)
{
  struct EV_Timer *timer = (struct EV_Timer *)xmalloc(sizeof(struct EV_Timer));

  return Data_Wrap_Struct(klass, EV_Timer_mark, EV_Timer_free, timer);
}

static void EV_Timer_mark(struct EV_Timer *timer)
{
  rb_gc_mark(timer->callback);
}

static void EV_Timer_free(struct EV_Timer *timer)
{
  xfree(timer);
}

static VALUE EV_Timer_initialize(VALUE self, VALUE after, VALUE repeat)
{
  printf("Timer_initialize\n");

  struct EV_Timer *timer;

  Data_Get_Struct(self, struct EV_Timer, timer);

  if (rb_block_given_p()) {
    timer->callback = rb_block_proc();
  }

  ev_timer_init(&timer->ev_timer, EV_Timer_callback, NUM2DBL(after), NUM2DBL(repeat));

  timer->self = self;
  timer->ev_timer.data = (void *)timer;

  ev_timer_start(EV_DEFAULT, &timer->ev_timer);

  return Qnil;
}

/* libev callback fired on IO event */
void EV_Timer_callback(ev_loop *ev_loop, struct ev_timer *timer, int revents)
{
  struct EV_Timer *timer_data = (struct EV_Timer *)timer->data;
  rb_funcall(timer_data->callback, rb_intern("call"), 1, Qtrue);
}

static VALUE EV_Timer_start(VALUE self)
{
  struct EV_Timer *timer;
  Data_Get_Struct(self, struct EV_Timer, timer);

  ev_timer_start(EV_DEFAULT, &timer->ev_timer);

  return Qnil;
}

static VALUE EV_Timer_stop(VALUE self)
{
  struct EV_Timer *timer;
  Data_Get_Struct(self, struct EV_Timer, timer);

  ev_timer_stop(EV_DEFAULT, &timer->ev_timer);

  return Qnil;
}
