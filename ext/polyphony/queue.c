#include "polyphony.h"

typedef struct queue {
  VALUE items;
  VALUE shift_waiters;
} Queue_t;

VALUE cQueue = Qnil;

static void Queue_mark(void *ptr) {
  Queue_t *queue = ptr;
  if (queue->items != Qnil) {
    rb_gc_mark(queue->items);
  }
  if (queue->shift_waiters != Qnil) {
    rb_gc_mark(queue->shift_waiters);
  }
}

static size_t Queue_size(const void *ptr) {
  return sizeof(Queue_t);
}

static const rb_data_type_t Queue_type = {
  "Queue",
  {Queue_mark, RUBY_DEFAULT_FREE, Queue_size,},
  0, 0, 0
};

static VALUE Queue_allocate(VALUE klass) {
  Queue_t *queue;
  // return Data_Make_Struct(klass, Queue_t, Queue_mark, free, queue);

  queue = ALLOC(Queue_t);
  // struct Queue *queue = ALLOC(struct Queue);
  return TypedData_Wrap_Struct(klass, &Queue_type, queue);
}

#define GetQueue(obj, queue) \
  TypedData_Get_Struct((obj), Queue_t, &Queue_type, (queue))

static VALUE Queue_initialize(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  queue->items = rb_ary_new();
  queue->shift_waiters = rb_ary_new();

  return self;
}

VALUE Queue_push(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  if (RARRAY_LEN(queue->shift_waiters) > 0) {
    VALUE watcher = rb_ary_shift(queue->shift_waiters);
    rb_funcall(watcher, ID_signal, 1, Qnil);
  }

  rb_ary_push(queue->items, value);
  return self;
}

VALUE Queue_shift(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  if (RARRAY_LEN(queue->items) == 0) {
    VALUE ret;
    VALUE watcher = Fiber_auto_watcher(rb_fiber_current());
    rb_ary_push(queue->shift_waiters, watcher);
    ret = rb_funcall(watcher, ID_await_no_raise, 0);
    if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
      rb_ary_delete(queue->shift_waiters, watcher);
      return rb_funcall(rb_mKernel, ID_raise, 1, ret);
    }
    RB_GC_GUARD(ret);
  }

  return rb_ary_shift(queue->items);
}

VALUE Queue_shift_no_wait(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return rb_ary_shift(queue->items);
}

VALUE Queue_shift_each(VALUE self) {
  Queue_t *queue;
  VALUE old_queue;
  GetQueue(self, queue);
  old_queue = queue->items;
  queue->items = rb_ary_new();

  if (rb_block_given_p()) {
    long len = RARRAY_LEN(old_queue);
    long i;
    for (i = 0; i < len; i++) {
      rb_yield(RARRAY_AREF(old_queue, i));
    }
    RB_GC_GUARD(old_queue);
    return self;
  }
  else {
    RB_GC_GUARD(old_queue);
    return old_queue;
  }
}

VALUE Queue_clear(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  rb_ary_clear(queue->items);
  return self;
}

VALUE Queue_empty_p(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return (RARRAY_LEN(queue->items) == 0) ? Qtrue : Qfalse;
}

void Init_Queue() {
  cQueue = rb_define_class_under(mPolyphony, "Queue", rb_cData);
  rb_define_alloc_func(cQueue, Queue_allocate);

  rb_define_method(cQueue, "initialize", Queue_initialize, 0);
  rb_define_method(cQueue, "push", Queue_push, 1);
  rb_define_method(cQueue, "<<", Queue_push, 1);

  rb_define_method(cQueue, "pop", Queue_shift, 0);
  rb_define_method(cQueue, "shift", Queue_shift, 0);

  rb_define_method(cQueue, "shift_no_wait", Queue_shift_no_wait, 0);

  rb_define_method(cQueue, "shift_each", Queue_shift_each, 0);
  rb_define_method(cQueue, "clear", Queue_clear, 0);
  rb_define_method(cQueue, "empty?", Queue_empty_p, 0);
}


