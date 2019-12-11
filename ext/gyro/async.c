#include "gyro.h"

struct Gyro_Async {
  struct  ev_async ev_async;
  int     active;
  VALUE   fiber;
};

static VALUE cGyro_Async = Qnil;

/* Allocator/deallocator */
static VALUE Gyro_Async_allocate(VALUE klass);
static void Gyro_Async_mark(void *ptr);
static void Gyro_Async_free(void *ptr);
static size_t Gyro_Async_size(const void *ptr);

/* Methods */
static VALUE Gyro_Async_initialize(VALUE self);

static VALUE Gyro_Async_signal(VALUE self);
static VALUE Gyro_Async_await(VALUE self);

void Gyro_Async_callback(struct ev_loop *ev_loop, struct ev_async *async, int revents);

/* async encapsulates an async watcher */
void Init_Gyro_Async() {
  cGyro_Async = rb_define_class_under(mGyro, "Async", rb_cData);
  rb_define_alloc_func(cGyro_Async, Gyro_Async_allocate);

  rb_define_method(cGyro_Async, "initialize", Gyro_Async_initialize, 0);
  rb_define_method(cGyro_Async, "signal!", Gyro_Async_signal, 0);
  rb_define_method(cGyro_Async, "await", Gyro_Async_await, 0);
}

static const rb_data_type_t Gyro_Async_type = {
    "Gyro_Async",
    {Gyro_Async_mark, Gyro_Async_free, Gyro_Async_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE Gyro_Async_allocate(VALUE klass) {
  struct Gyro_Async *async = (struct Gyro_Async *)xmalloc(sizeof(struct Gyro_Async));
  return TypedData_Wrap_Struct(klass, &Gyro_Async_type, async);
}

static void Gyro_Async_mark(void *ptr) {
  struct Gyro_Async *async = ptr;
  if (async->fiber != Qnil) {
    rb_gc_mark(async->fiber);
  }
}

static void Gyro_Async_free(void *ptr) {
  struct Gyro_Async *async = ptr;
  ev_async_stop(EV_DEFAULT, &async->ev_async);
  xfree(async);
}

static size_t Gyro_Async_size(const void *ptr) {
  return sizeof(struct Gyro_Async);
}

#define GetGyro_Async(obj, async) \
  TypedData_Get_Struct((obj), struct Gyro_Async, &Gyro_Async_type, (async))

static VALUE Gyro_Async_initialize(VALUE self) {
  struct Gyro_Async *async;
  GetGyro_Async(self, async);

  async->fiber = Qnil;
  async->active = 0;

  ev_async_init(&async->ev_async, Gyro_Async_callback);

  return Qnil;
}

void Gyro_Async_callback(struct ev_loop *ev_loop, struct ev_async *ev_async, int revents) {
  VALUE fiber;
  struct Gyro_Async *async = (struct Gyro_Async*)ev_async;

  if (async->fiber != Qnil) {
    ev_async_stop(EV_DEFAULT, ev_async);
    async->active = 0;
    fiber = async->fiber;
    async->fiber = Qnil;
    SCHEDULE_FIBER(fiber, 0);
  }
  else {
    ev_async_stop(EV_DEFAULT, ev_async);
  }
}

static VALUE Gyro_Async_signal(VALUE self) {
  struct Gyro_Async *async;
  GetGyro_Async(self, async);

  ev_async_send(EV_DEFAULT, &async->ev_async);

  return Qnil;
}

static VALUE Gyro_Async_await(VALUE self) {
  struct Gyro_Async *async;
  VALUE ret;
  
  GetGyro_Async(self, async);

  async->fiber = rb_fiber_current();
  if (!async->active) {
    async->active = 1;
    ev_async_start(EV_DEFAULT, &async->ev_async);
  }

  ret = YIELD_TO_REACTOR();

  // fiber is resumed
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    if (async->active) {
      async->active = 0;
      ev_async_stop(EV_DEFAULT, &async->ev_async);
    }
    return rb_funcall(ret, ID_raise, 1, ret);
  }
  else {
    return Qnil;
  }
}