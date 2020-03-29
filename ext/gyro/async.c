#include "gyro.h"

struct Gyro_Async {
  struct  ev_async ev_async;
  struct  ev_loop *ev_loop;
  int     active;
  VALUE   fiber;
  VALUE   value;
};

VALUE cGyro_Async = Qnil;

static void Gyro_Async_mark(void *ptr) {
  struct Gyro_Async *async = ptr;
  if (async->fiber != Qnil) {
    rb_gc_mark(async->fiber);
  }
  if (async->value != Qnil) {
    rb_gc_mark(async->value);
  }
}

static void Gyro_Async_free(void *ptr) {
  struct Gyro_Async *async = ptr;
  if (async->active) {
    printf("Async watcher garbage collected while still active!\n");
  }
  xfree(async);
}

static size_t Gyro_Async_size(const void *ptr) {
  return sizeof(struct Gyro_Async);
}

static const rb_data_type_t Gyro_Async_type = {
    "Gyro_Async",
    {Gyro_Async_mark, Gyro_Async_free, Gyro_Async_size,},
    0, 0, 0
};

static VALUE Gyro_Async_allocate(VALUE klass) {
  struct Gyro_Async *async = ALLOC(struct Gyro_Async);
  return TypedData_Wrap_Struct(klass, &Gyro_Async_type, async);
}

void Gyro_Async_callback(struct ev_loop *ev_loop, struct ev_async *ev_async, int revents) {
  struct Gyro_Async *async = (struct Gyro_Async*)ev_async;

  ev_async_stop(async->ev_loop, ev_async);
  async->active = 0;

  if (async->fiber != Qnil) {
    Gyro_schedule_fiber(async->fiber, async->value);
    async->fiber = Qnil;
    async->value = Qnil;
  }
}

#define GetGyro_Async(obj, async) \
  TypedData_Get_Struct((obj), struct Gyro_Async, &Gyro_Async_type, (async))

static VALUE Gyro_Async_initialize(VALUE self) {
  struct Gyro_Async *async;
  GetGyro_Async(self, async);

  async->fiber = Qnil;
  async->value = Qnil;
  async->active = 0;

  ev_async_init(&async->ev_async, Gyro_Async_callback);
  async->ev_loop = 0;

  return Qnil;
}

static VALUE Gyro_Async_signal(int argc, VALUE *argv, VALUE self) {
  struct Gyro_Async *async;
  GetGyro_Async(self, async);

  if (!async->active) {
    // printf("signal! called before await\n");
    return Qnil;
  }

  async->value = (argc == 1) ? argv[0] : Qnil;
  ev_async_send(async->ev_loop, &async->ev_async);

  return Qnil;
}

VALUE Gyro_Async_await(VALUE self) {
  struct Gyro_Async *async;
  VALUE ret;
  
  GetGyro_Async(self, async);

  async->fiber = rb_fiber_current();
  if (!async->active) {
    async->active = 1;
    async->ev_loop = Gyro_Selector_current_thread_ev_loop();
    ev_async_start(async->ev_loop, &async->ev_async);
  }

  ret = Fiber_await();
  RB_GC_GUARD(ret);

  if (async->active) {
    async->active = 0;
    async->fiber = Qnil;
    ev_async_stop(async->ev_loop, &async->ev_async);
    async->value = Qnil;
  }

  // fiber is resumed
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    return rb_funcall(rb_mKernel, ID_raise, 1, ret);
  }
  else {
    return ret;
  }
}

VALUE Gyro_Async_await_no_raise(VALUE self) {
  struct Gyro_Async *async;
  VALUE ret;
  
  GetGyro_Async(self, async);

  async->fiber = rb_fiber_current();
  if (!async->active) {
    async->active = 1;
    async->ev_loop = Gyro_Selector_current_thread_ev_loop();
    ev_async_start(async->ev_loop, &async->ev_async);
  }

  ret = Fiber_await();
  RB_GC_GUARD(ret);

  if (async->active) {
    async->active = 0;
    async->fiber = Qnil;
    ev_async_stop(async->ev_loop, &async->ev_async);
    async->value = Qnil;
  }

  return ret;
}


void Init_Gyro_Async() {
  cGyro_Async = rb_define_class_under(mGyro, "Async", rb_cData);
  rb_define_alloc_func(cGyro_Async, Gyro_Async_allocate);

  rb_define_method(cGyro_Async, "initialize", Gyro_Async_initialize, 0);
  rb_define_method(cGyro_Async, "signal!", Gyro_Async_signal, -1);
  rb_define_method(cGyro_Async, "await", Gyro_Async_await, 0);
}
