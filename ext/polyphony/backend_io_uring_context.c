#include <stdlib.h>
#include <assert.h>
#include "ruby.h"
#include "polyphony.h"
#include "backend_io_uring_context.h"

const char *op_type_to_str(enum op_type type) {
  switch (type) {
  case OP_READ: return "READ";
  case OP_WRITEV: return "WRITEV";
  case OP_WRITE: return "WRITE";
  case OP_RECV: return "RECV";
  case OP_SEND: return "SEND";
  case OP_SPLICE: return "SPLICE";
  case OP_TIMEOUT: return "TIMEOUT";
  case OP_POLL: return "POLL";
  case OP_ACCEPT: return "ACCEPT";
  case OP_CONNECT: return "CONNECT";
  case OP_CHAIN: return "CHAIN";
  default: return "";
  };
}

void context_store_initialize(op_context_store_t *store) {
  store->last_id = 0;
  store->available = NULL;
  store->taken = NULL;
  store->available_count = 0;
  store->taken_count = 0;
}

inline op_context_t *context_store_acquire(op_context_store_t *store, enum op_type type) {
  op_context_t *ctx = store->available;
  if (ctx) {
    if (ctx->next) ctx->next->prev = NULL;
    store->available = ctx->next;
    store->available_count--;
  }
  else {
    ctx = malloc(sizeof(op_context_t));
  }
  ctx->id = (++store->last_id);
  ctx->prev = NULL;
  ctx->next = store->taken;
  if (store->taken) store->taken->prev = ctx;
  store->taken = ctx;

  ctx->type = type;
  ctx->fiber = rb_fiber_current();
  ctx->resume_value = Qnil;
  ctx->ref_count = 2;
  ctx->result = 0;
  ctx->buffer_count = 0;

  store->taken_count++;

  // printf("acquire %p %d (%s, ref_count: %d) taken: %d\n", ctx, ctx->id, op_type_to_str(type), ctx->ref_count, store->taken_count);

  return ctx;
}

// returns true if ctx was released
inline int context_store_release(op_context_store_t *store, op_context_t *ctx) {
  // printf("release %p %d (%s, ref_count: %d)\n", ctx, ctx->id, op_type_to_str(ctx->type), ctx->ref_count);

  assert(ctx->ref_count);
  
  ctx->ref_count--;
  if (ctx->ref_count) return 0;

  if (ctx->buffer_count > 1) free(ctx->buffers);

  store->taken_count--;
  store->available_count++;

  if (ctx->next) ctx->next->prev = ctx->prev;
  if (ctx->prev) ctx->prev->next = ctx->next;
  if (store->taken == ctx) store->taken = ctx->next;

  ctx->prev = NULL;
  ctx->next = store->available;
  if (ctx->next) ctx->next->prev = ctx;
  store->available = ctx;
  return 1;
}

void context_store_free(op_context_store_t *store) {
  while (store->available) {
    op_context_t *next = store->available->next;
    free(store->available);
    store->available = next;
  }
  while (store->taken) {
    op_context_t *next = store->taken->next;
    free(store->taken);
    store->taken = next;
  }
}

inline void context_store_mark_taken_buffers(op_context_store_t *store) {
  op_context_t *ctx = store->taken;
  while (ctx) {
    for (unsigned int i = 0; i < ctx->buffer_count; i++)
      rb_gc_mark(i == 0 ? ctx->buffer0 : ctx->buffers[i - 1]);
    ctx = ctx->next;
  }
}

inline void context_attach_buffers(op_context_t *ctx, unsigned int count, VALUE *buffers) {
  // attaching buffers to the context is done in order to ensure that any GC
  // pass done before the context is released will mark those buffers, even if
  // the fiber has already been resumed and the buffers are not in use anymore.
  // This is done in order to prevent a possible race condition where on the
  // kernel side the buffers are still in use, but in userspace they have
  // effectively been freed after a GC pass.
  ctx->buffer_count = count;
  if (count > 1)
    ctx->buffers = malloc(sizeof(VALUE) * (count - 1));
  for (unsigned int i = 0; i < count; i++)
    if (!i) ctx->buffer0 = buffers[0];
    else    ctx->buffers[i - 1] = buffers[i];
}

inline void context_attach_buffers_v(op_context_t *ctx, unsigned int count, ...) {
  va_list values;

  va_start(values, count);

  ctx->buffer_count = count;
  if (count > 1)
    ctx->buffers = malloc(sizeof(VALUE) * (count - 1));
  for (unsigned int i = 0; i < count; i++)
    if (!i) ctx->buffer0 = va_arg(values, VALUE);
    else    ctx->buffers[i - 1] = va_arg(values, VALUE);

  va_end(values);
}