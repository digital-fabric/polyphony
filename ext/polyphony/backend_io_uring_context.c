#include <stdlib.h>
#include "ruby.h"
#include "backend_io_uring_context.h"

const char *op_type_to_str(enum op_type type) {
  switch (type) {
  case OP_READV: return "READV";
  case OP_WRITEV: return "WRITEV";
  case OP_RECV: return "RECV";
  case OP_SEND: return "SEND";
  case OP_TIMEOUT: return "TIMEOUT";
  case OP_POLL: return "POLL";
  case OP_ACCEPT: return "ACCEPT";
  case OP_CONNECT: return "CONNECT";
  default: return "";
  };
}

void context_store_initialize(op_context_store_t *store) {
  store->available = NULL;
  store->taken = NULL;
}

inline op_context_t *context_store_borrow(op_context_store_t *store, enum op_type type) {
  op_context_t *ctx = store->available;
  if (ctx)
    store->available = ctx->next;
  else
    ctx = malloc(sizeof(op_context_t));
  
  ctx->next = store->taken;
  store->taken = ctx;

  ctx->type = type;
  ctx->fiber = rb_fiber_current();
  ctx->completed = 0;
  return ctx;
}

inline void context_store_return(op_context_store_t *store, op_context_t *ctx) {
  store->taken = ctx->next;
  ctx->next = store->available;
  store->available = ctx;
}

void context_store_free(op_context_store_t *store) {
  op_context_t *ptr = store->available;
  while (ptr) {
    op_context_t *next = ptr->next;
    free(ptr);
    ptr = next;
  }
  ptr = store->taken;
  while (ptr) {
    op_context_t *next = ptr->next;
    free(ptr);
    ptr = next;
  }
}
