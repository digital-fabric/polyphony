#include "polyphony.h"
#include "ring_buffer.h"

typedef struct queue {
  ring_buffer values;
  ring_buffer shift_queue;
} Queue_t;

VALUE cQueue = Qnil;

static void Queue_mark(void *ptr) {
  Queue_t *queue = ptr;
  ring_buffer_mark(&queue->values);
  ring_buffer_mark(&queue->shift_queue);
}

static void Queue_free(void *ptr) {
  Queue_t *queue = ptr;
  ring_buffer_free(&queue->values);
  ring_buffer_free(&queue->shift_queue);
  xfree(ptr);
}

static size_t Queue_size(const void *ptr) {
  return sizeof(Queue_t);
}

static const rb_data_type_t Queue_type = {
  "Queue",
  {Queue_mark, Queue_free, Queue_size,},
  0, 0, 0
};

static VALUE Queue_allocate(VALUE klass) {
  Queue_t *queue;

  queue = ALLOC(Queue_t);
  return TypedData_Wrap_Struct(klass, &Queue_type, queue);
}

#define GetQueue(obj, queue) \
  TypedData_Get_Struct((obj), Queue_t, &Queue_type, (queue))

static VALUE Queue_initialize(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  ring_buffer_init(&queue->values);
  ring_buffer_init(&queue->shift_queue);

  return self;
}

VALUE Queue_push(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  if (queue->shift_queue.count > 0) {
    VALUE fiber = ring_buffer_shift(&queue->shift_queue);
    if (fiber != Qnil) Fiber_make_runnable(fiber, Qnil);
  }
  ring_buffer_push(&queue->values, value);
  return self;
}

VALUE Queue_unshift(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);
  if (queue->shift_queue.count > 0) {
    VALUE fiber = ring_buffer_shift(&queue->shift_queue);
    if (fiber != Qnil) Fiber_make_runnable(fiber, Qnil);
  }
  ring_buffer_unshift(&queue->values, value);
  return self;
}

VALUE Queue_shift(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  VALUE fiber = rb_fiber_current();
  VALUE thread = rb_thread_current();
  VALUE backend = rb_ivar_get(thread, ID_ivar_backend);

  while (1) {
    ring_buffer_push(&queue->shift_queue, fiber);
    if (queue->values.count > 0) Fiber_make_runnable(fiber, Qnil);

    VALUE switchpoint_result = __BACKEND__.wait_event(backend, Qnil);
    ring_buffer_delete(&queue->shift_queue, fiber);

    RAISE_IF_EXCEPTION(switchpoint_result);
    RB_GC_GUARD(switchpoint_result);

    if (queue->values.count > 0)
      return ring_buffer_shift(&queue->values);
  }

  return Qnil;
}

VALUE Queue_shift_no_wait(VALUE self) {
    Queue_t *queue;
  GetQueue(self, queue);

  return ring_buffer_shift(&queue->values);
}

VALUE Queue_delete(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  ring_buffer_delete(&queue->values, value);
  return self;
}

VALUE Queue_clear(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  ring_buffer_clear(&queue->values);
  return self;
}

long Queue_len(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return queue->values.count;
}

VALUE Queue_shift_each(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  ring_buffer_shift_each(&queue->values);
  return self;
}

VALUE Queue_shift_all(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return ring_buffer_shift_all(&queue->values);
}

VALUE Queue_flush_waiters(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  while(1) {
    VALUE fiber = ring_buffer_shift(&queue->shift_queue);
    if (fiber == Qnil) return self;

    Fiber_make_runnable(fiber, value);
  }
}

VALUE Queue_empty_p(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return (queue->values.count == 0) ? Qtrue : Qfalse;
}

VALUE Queue_pending_p(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return (queue->shift_queue.count > 0) ? Qtrue : Qfalse;
}

VALUE Queue_size_m(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return INT2NUM(queue->values.count);
}

void Queue_trace(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  printf("run queue size: %d count: %d\n", queue->values.size, queue->values.count);
}

void Init_Queue() {
  cQueue = rb_define_class_under(mPolyphony, "Queue", rb_cData);
  rb_define_alloc_func(cQueue, Queue_allocate);

  rb_define_method(cQueue, "initialize", Queue_initialize, 0);
  rb_define_method(cQueue, "push", Queue_push, 1);
  rb_define_method(cQueue, "<<", Queue_push, 1);
  rb_define_method(cQueue, "unshift", Queue_unshift, 1);

  rb_define_method(cQueue, "shift", Queue_shift, 0);
  rb_define_method(cQueue, "pop", Queue_shift, 0);
  rb_define_method(cQueue, "shift_no_wait", Queue_shift_no_wait, 0);
  rb_define_method(cQueue, "delete", Queue_delete, 1);

  rb_define_method(cQueue, "shift_each", Queue_shift_each, 0);
  rb_define_method(cQueue, "shift_all", Queue_shift_all, 0);
  rb_define_method(cQueue, "flush_waiters", Queue_flush_waiters, 1);
  rb_define_method(cQueue, "empty?", Queue_empty_p, 0);
  rb_define_method(cQueue, "pending?", Queue_pending_p, 0);
  rb_define_method(cQueue, "size", Queue_size_m, 0);
}
