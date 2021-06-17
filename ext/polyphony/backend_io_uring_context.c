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
}

inline op_context_t *context_store_acquire(op_context_store_t *store, enum op_type type) {
  op_context_t *ctx = store->available;
  if (ctx) {
    if (ctx->next) ctx->next->prev = NULL;
    store->available = ctx->next;
  }
  else {
    ctx = malloc(sizeof(op_context_t));
  }
  ctx->id = (++store->last_id);
  // printf("acquire %d (%s)\n", ctx->id, op_type_to_str(type));
  
  ctx->prev = NULL;
  ctx->next = store->taken;
  if (store->taken) store->taken->prev = ctx;
  store->taken = ctx;

  ctx->type = type;
  ctx->fiber = rb_fiber_current();
  ctx->resume_value = Qnil;
  ctx->ref_count = 2;
  ctx->result = 0;

  return ctx;
}

// returns true if ctx was released
inline int context_store_release(op_context_store_t *store, op_context_t *ctx) {
  // printf("release %d (%s, ref_count: %d)\n", ctx->id, op_type_to_str(ctx->type), ctx->ref_count);

  assert(ctx->ref_count);
  
  ctx->ref_count--;
  if (ctx->ref_count) return 0;

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
