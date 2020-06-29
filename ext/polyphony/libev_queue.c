#include "polyphony.h"

struct async_watcher {
  ev_async async;
  struct ev_loop *ev_loop;
  VALUE fiber;
};

struct async_queue {
  struct async_watcher **queue;
  unsigned int len;
  unsigned int count;
  unsigned int push_idx;
  unsigned int pop_idx;
};

void async_queue_init(struct async_queue *queue) {
  queue->len = 4;
  queue->count = 0;
  queue->queue = malloc(sizeof(struct async_watcher *) * queue->len);
  queue->push_idx = 0;
  queue->pop_idx = 0;
}

void async_queue_free(struct async_queue *queue) {
  free(queue->queue);
}

void async_queue_push(struct async_queue *queue, struct async_watcher *watcher) {
  if (queue->push_idx == queue->len) {
    queue->len = queue->len * 2;
    queue->queue = realloc(queue->queue, sizeof(struct async_watcher *) * queue->len);
  }
  if (queue->count == 0) {
    queue->push_idx = 0;
    queue->pop_idx = 0;
  }
  queue->count++;
  queue->queue[queue->push_idx++] = watcher;
}

struct async_watcher *async_queue_pop(struct async_queue *queue) {
  if (queue->count == 0) return 0;

  queue->count--;

  return queue->queue[queue->pop_idx++];
}

void async_queue_remove_at_idx(struct async_queue *queue, unsigned int remove_idx) {
  queue->count--;
  queue->push_idx--;
  if (remove_idx < queue->push_idx)
    memmove(
      queue->queue + remove_idx,
      queue->queue + remove_idx + 1,
      (queue->push_idx - remove_idx) * sizeof(struct async_watcher *)
    );
}

void async_queue_remove_by_fiber(struct async_queue *queue, VALUE fiber) {
  if (queue->count == 0) return;

  for (unsigned idx = queue->pop_idx; idx < queue->push_idx; idx++) {
    if (queue->queue[idx]->fiber == fiber) {
      async_queue_remove_at_idx(queue, idx);
      return; 
    }
  }
}

typedef struct queue {
  VALUE items;
  struct async_queue shift_queue;
} LibevQueue_t;


VALUE cLibevQueue = Qnil;

static void LibevQueue_mark(void *ptr) {
  LibevQueue_t *queue = ptr;
  rb_gc_mark(queue->items);
}

static void LibevQueue_free(void *ptr) {
  LibevQueue_t *queue = ptr;
  async_queue_free(&queue->shift_queue);
  xfree(ptr);
}

static size_t LibevQueue_size(const void *ptr) {
  return sizeof(LibevQueue_t);
}

static const rb_data_type_t LibevQueue_type = {
  "Queue",
  {LibevQueue_mark, LibevQueue_free, LibevQueue_size,},
  0, 0, 0
};

static VALUE LibevQueue_allocate(VALUE klass) {
  LibevQueue_t *queue;

  queue = ALLOC(LibevQueue_t);
  return TypedData_Wrap_Struct(klass, &LibevQueue_type, queue);
}

#define GetQueue(obj, queue) \
  TypedData_Get_Struct((obj), LibevQueue_t, &LibevQueue_type, (queue))

static VALUE LibevQueue_initialize(VALUE self) {
  LibevQueue_t *queue;
  GetQueue(self, queue);

  queue->items = rb_ary_new();
  async_queue_init(&queue->shift_queue);

  return self;
}

VALUE LibevQueue_push(VALUE self, VALUE value) {
  LibevQueue_t *queue;
  struct async_watcher *watcher;
  GetQueue(self, queue);
  watcher = async_queue_pop(&queue->shift_queue);
  if (watcher) {
    ev_async_send(watcher->ev_loop, &watcher->async);
  }
  rb_ary_push(queue->items, value);
  return self;
}

struct ev_loop *LibevAgent_ev_loop(VALUE self);

void async_queue_callback(struct ev_loop *ev_loop, struct ev_async *ev_async, int revents) {
  struct async_watcher *watcher = (struct async_watcher *)ev_async;
  Fiber_make_runnable(watcher->fiber, Qnil);
}

VALUE libev_agent_await(VALUE self);

VALUE LibevQueue_shift(VALUE self) {
  LibevQueue_t *queue;
  GetQueue(self, queue);

  if (RARRAY_LEN(queue->items) == 0) {
    struct async_watcher watcher;
    VALUE agent = rb_ivar_get(rb_thread_current(), ID_ivar_agent);
    VALUE switchpoint_result = Qnil;

    watcher.ev_loop = LibevAgent_ev_loop(agent);
    watcher.fiber = rb_fiber_current();    
    async_queue_push(&queue->shift_queue, &watcher);
    ev_async_init(&watcher.async, async_queue_callback);
    ev_async_start(watcher.ev_loop, &watcher.async);
    
    switchpoint_result = libev_agent_await(agent);
    ev_async_stop(watcher.ev_loop, &watcher.async);

    if (RTEST(rb_obj_is_kind_of(switchpoint_result, rb_eException))) {
      async_queue_remove_by_fiber(&queue->shift_queue, watcher.fiber);
      return rb_funcall(rb_mKernel, ID_raise, 1, switchpoint_result);
    }
    RB_GC_GUARD(watcher.fiber);
    RB_GC_GUARD(agent);
    RB_GC_GUARD(switchpoint_result);
  }

  return rb_ary_shift(queue->items);
}

VALUE LibevQueue_shift_each(VALUE self) {
  LibevQueue_t *queue;
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

VALUE LibevQueue_empty_p(VALUE self) {
  LibevQueue_t *queue;
  GetQueue(self, queue);

  return (RARRAY_LEN(queue->items) == 0) ? Qtrue : Qfalse;
}

void Init_LibevQueue() {
  cLibevQueue = rb_define_class_under(mPolyphony, "LibevQueue", rb_cData);
  rb_define_alloc_func(cLibevQueue, LibevQueue_allocate);

  rb_define_method(cLibevQueue, "initialize", LibevQueue_initialize, 0);
  rb_define_method(cLibevQueue, "push", LibevQueue_push, 1);
  rb_define_method(cLibevQueue, "<<", LibevQueue_push, 1);

  rb_define_method(cLibevQueue, "pop", LibevQueue_shift, 0);
  rb_define_method(cLibevQueue, "shift", LibevQueue_shift, 0);

  rb_define_method(cLibevQueue, "shift_each", LibevQueue_shift_each, 0);
  rb_define_method(cLibevQueue, "empty?", LibevQueue_empty_p, 0);
}


