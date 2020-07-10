#include "polyphony.h"

struct async_watcher {
  ev_async async;
  struct ev_loop *ev_loop;
  VALUE fiber;
};

struct async_watcher_queue {
  struct async_watcher **queue;
  unsigned int length;
  unsigned int count;
  unsigned int push_idx;
  unsigned int shift_idx;
};

void async_watcher_queue_init(struct async_watcher_queue *queue) {
  queue->length = 1;
  queue->count = 0;
  queue->queue = malloc(sizeof(struct async_watcher *) * queue->length);
  queue->push_idx = 0;
  queue->shift_idx = 0;
}

void async_watcher_queue_free(struct async_watcher_queue *queue) {
  free(queue->queue);
}

void async_watcher_queue_realign(struct async_watcher_queue *queue) {
  memmove(
    queue->queue,
    queue->queue + queue->shift_idx,
    queue->count * sizeof(struct async_watcher *)
  );
  queue->push_idx = queue->push_idx - queue->shift_idx;
  queue->shift_idx = 0;
}

#define QUEUE_REALIGN_THRESHOLD 32

void async_watcher_queue_push(struct async_watcher_queue *queue, struct async_watcher *watcher) {
  if (queue->count == 0) {
    queue->push_idx = 0;
    queue->shift_idx = 0;
  }
  if (queue->push_idx == queue->length) {
    // prevent shift idx moving too much away from zero
    if (queue->length >= QUEUE_REALIGN_THRESHOLD && queue->shift_idx >= (queue->length / 2))
      async_watcher_queue_realign(queue);
    else {
      queue->length = (queue->length == 1) ? 4 : queue->length * 2;
      queue->queue = realloc(queue->queue, sizeof(struct async_watcher *) * queue->length);
    }
  }
  queue->count++;
  queue->queue[queue->push_idx++] = watcher;
}

struct async_watcher *async_watcher_queue_shift(struct async_watcher_queue *queue) {
  if (queue->count == 0) return 0;

  queue->count--;

  return queue->queue[queue->shift_idx++];
}

void async_watcher_queue_remove_at_idx(struct async_watcher_queue *queue, unsigned int remove_idx) {
  queue->count--;
  queue->push_idx--;
  if (remove_idx < queue->push_idx)
    memmove(
      queue->queue + remove_idx,
      queue->queue + remove_idx + 1,
      (queue->push_idx - remove_idx) * sizeof(struct async_watcher *)
    );
}

void async_watcher_queue_remove_by_fiber(struct async_watcher_queue *queue, VALUE fiber) {
  if (queue->count == 0) return;

  for (unsigned idx = queue->shift_idx; idx < queue->push_idx; idx++) {
    if (queue->queue[idx]->fiber == fiber) {
      async_watcher_queue_remove_at_idx(queue, idx);
      return; 
    }
  }
}

struct value_queue {
  VALUE *queue;
  unsigned int length;
  unsigned int count;
  unsigned int push_idx;
  unsigned int shift_idx;
};

void value_queue_init(struct value_queue *queue) {
  queue->length = 1;
  queue->count = 0;
  queue->queue = malloc(queue->length * sizeof(VALUE));
  queue->push_idx = 0;
  queue->shift_idx = 0;
}

void value_queue_mark(struct value_queue *queue) {
  for (unsigned int idx = queue->shift_idx; idx < queue->push_idx; idx++) {
    rb_gc_mark(queue->queue[idx]);
  }
}

void value_queue_free(struct value_queue *queue) {
  free(queue->queue);
}

void value_queue_realign(struct value_queue *queue) {
  memmove(
    queue->queue,
    queue->queue + queue->shift_idx,
    queue->count * sizeof(VALUE)
  );
  queue->push_idx = queue->push_idx - queue->shift_idx;
  queue->shift_idx = 0;
}

#define QUEUE_REALIGN_THRESHOLD 32

void value_queue_push(struct value_queue *queue, VALUE value) {
  if (queue->count == 0) {
    queue->push_idx = 0;
    queue->shift_idx = 0;
  }
  if (queue->push_idx == queue->length) {
    // prevent shift idx moving too much away from zero
    if (queue->length >= QUEUE_REALIGN_THRESHOLD && queue->shift_idx >= (queue->length / 2))
      value_queue_realign(queue);
    else {
      queue->length = (queue->length == 1) ? 4 : queue->length * 2;
      queue->queue = realloc(queue->queue, queue->length * sizeof(VALUE));
    }
  }
  queue->count++;
  queue->queue[queue->push_idx++] = value;
}

void value_queue_unshift(struct value_queue *queue, VALUE value) {
  if (queue->count == 0) {
    queue->shift_idx = 0;
    queue->push_idx = 0;
  }
  if (queue->shift_idx > 0)
    queue->queue[--queue->shift_idx] = value;
  else {
    if (queue->count == queue->length) {
      queue->length = (queue->length == 1) ? 4 : queue->length * 2;
      queue->queue = realloc(queue->queue, queue->length * sizeof(VALUE));
    }
    memmove(queue->queue + 1, queue->queue, queue->count * sizeof(VALUE));
    queue->push_idx++;
  }
  queue->queue[queue->shift_idx] = value;
  queue->count++;
}

VALUE value_queue_shift(struct value_queue *queue) {
  if (queue->count == 0) return Qnil;

  queue->count--;
  return queue->queue[queue->shift_idx++];
}

void value_queue_remove_at_idx(struct value_queue *queue, unsigned int remove_idx) {
  queue->count--;
  queue->push_idx--;
  if (remove_idx < queue->push_idx)
    memmove(
      queue->queue + remove_idx,
      queue->queue + remove_idx + 1,
      (queue->push_idx - remove_idx) * sizeof(VALUE)
    );
}

void value_queue_remove_by_value(struct value_queue *queue, VALUE value) {
  if (queue->count == 0) return;

  for (unsigned idx = queue->shift_idx; idx < queue->push_idx; idx++) {
    if (queue->queue[idx] == value) {
      value_queue_remove_at_idx(queue, idx);
      return; 
    }
  }
}

void value_queue_clear(struct value_queue *queue) {
  queue->count = 0;
}

void value_queue_shift_each(struct value_queue *queue) {
  if (queue->count == 0) return;

  for (unsigned int idx = queue->shift_idx; idx < queue->push_idx; idx++) {
    rb_yield(queue->queue[idx]);
  }
  queue->count = 0;
}

VALUE value_queue_shift_all(struct value_queue *queue) {
  VALUE ary;
  if (queue->count == 0)
    ary = rb_ary_new();
  else {
    ary = rb_ary_new_from_values(queue->count, queue->queue + queue->shift_idx);
    queue->count = 0; 
  }
  return ary;
}

typedef struct queue {
  struct value_queue items;
  struct async_watcher_queue shift_queue;
} LibevQueue_t;


VALUE cLibevQueue = Qnil;

static void LibevQueue_mark(void *ptr) {
  LibevQueue_t *queue = ptr;
  value_queue_mark(&queue->items);
  // rb_gc_mark(queue->items);
}

static void LibevQueue_free(void *ptr) {
  LibevQueue_t *queue = ptr;
  async_watcher_queue_free(&queue->shift_queue);
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

  value_queue_init(&queue->items);
  async_watcher_queue_init(&queue->shift_queue);

  return self;
}

VALUE LibevQueue_push(VALUE self, VALUE value) {
  LibevQueue_t *queue;
  GetQueue(self, queue);
  if (queue->shift_queue.count > 0) {
    struct async_watcher *watcher = async_watcher_queue_shift(&queue->shift_queue);
    if (watcher) {
      ev_async_send(watcher->ev_loop, &watcher->async);
    }
  }
  value_queue_push(&queue->items, value);
  return self;
}

VALUE LibevQueue_unshift(VALUE self, VALUE value) {
  LibevQueue_t *queue;
  GetQueue(self, queue);
  if (queue->shift_queue.count > 0) {
    struct async_watcher *watcher = async_watcher_queue_shift(&queue->shift_queue);
    if (watcher) {
      ev_async_send(watcher->ev_loop, &watcher->async);
    }
  }
  value_queue_unshift(&queue->items, value);
  return self;
}

struct ev_loop *LibevAgent_ev_loop(VALUE self);

void async_watcher_queue_callback(struct ev_loop *ev_loop, struct ev_async *ev_async, int revents) {
  struct async_watcher *watcher = (struct async_watcher *)ev_async;
  Fiber_make_runnable(watcher->fiber, Qnil);
}

VALUE libev_agent_await(VALUE self);

VALUE LibevQueue_shift(VALUE self) {
  LibevQueue_t *queue;
  GetQueue(self, queue);

  if (queue->items.count == 0) {
    struct async_watcher watcher;
    VALUE agent = rb_ivar_get(rb_thread_current(), ID_ivar_agent);
    VALUE switchpoint_result = Qnil;

    watcher.ev_loop = LibevAgent_ev_loop(agent);
    watcher.fiber = rb_fiber_current();    
    async_watcher_queue_push(&queue->shift_queue, &watcher);
    ev_async_init(&watcher.async, async_watcher_queue_callback);
    ev_async_start(watcher.ev_loop, &watcher.async);
    
    switchpoint_result = libev_agent_await(agent);
    ev_async_stop(watcher.ev_loop, &watcher.async);

    if (RTEST(rb_obj_is_kind_of(switchpoint_result, rb_eException))) {
      async_watcher_queue_remove_by_fiber(&queue->shift_queue, watcher.fiber);
      return rb_funcall(rb_mKernel, ID_raise, 1, switchpoint_result);
    }
    RB_GC_GUARD(watcher.fiber);
    RB_GC_GUARD(agent);
    RB_GC_GUARD(switchpoint_result);
  }

  return value_queue_shift(&queue->items);
}

VALUE LibevQueue_shift_no_wait(VALUE self) {
    LibevQueue_t *queue;
  GetQueue(self, queue);

  return value_queue_shift(&queue->items);
}

VALUE LibevQueue_delete(VALUE self, VALUE value) {
  LibevQueue_t *queue;
  GetQueue(self, queue);

  value_queue_remove_by_value(&queue->items, value);
  return self;
}

VALUE LibevQueue_clear(VALUE self) {
  LibevQueue_t *queue;
  GetQueue(self, queue);

  value_queue_clear(&queue->items);
  return self;
}

long LibevQueue_len(VALUE self) {
  LibevQueue_t *queue;
  GetQueue(self, queue);

  return queue->items.count;
}

VALUE LibevQueue_shift_each(VALUE self) {
  LibevQueue_t *queue;
  GetQueue(self, queue);

  value_queue_shift_each(&queue->items);
  return self;
}

VALUE LibevQueue_shift_all(VALUE self) {
  LibevQueue_t *queue;
  GetQueue(self, queue);

  return value_queue_shift_all(&queue->items);
}

VALUE LibevQueue_empty_p(VALUE self) {
  LibevQueue_t *queue;
  GetQueue(self, queue);

  return (queue->items.count == 0) ? Qtrue : Qfalse;
}

void Init_LibevQueue() {
  cLibevQueue = rb_define_class_under(mPolyphony, "LibevQueue", rb_cData);
  rb_define_alloc_func(cLibevQueue, LibevQueue_allocate);

  rb_define_method(cLibevQueue, "initialize", LibevQueue_initialize, 0);
  rb_define_method(cLibevQueue, "push", LibevQueue_push, 1);
  rb_define_method(cLibevQueue, "<<", LibevQueue_push, 1);
  rb_define_method(cLibevQueue, "unshift", LibevQueue_unshift, 1);

  rb_define_method(cLibevQueue, "shift", LibevQueue_shift, 0);
  rb_define_method(cLibevQueue, "pop", LibevQueue_shift, 0);
  rb_define_method(cLibevQueue, "shift_no_wait", LibevQueue_shift_no_wait, 0);
  rb_define_method(cLibevQueue, "delete", LibevQueue_delete, 1);

  rb_define_method(cLibevQueue, "shift_each", LibevQueue_shift_each, 0);
  rb_define_method(cLibevQueue, "shift_all", LibevQueue_shift_all, 0);
  rb_define_method(cLibevQueue, "empty?", LibevQueue_empty_p, 0);
}


