#ifndef BACKEND_IO_URING_CONTEXT_H
#define BACKEND_IO_URING_CONTEXT_H

#include "ruby.h"

enum op_type {
  OP_NONE,
  OP_READV,
  OP_WRITEV,
  OP_WRITE,
  OP_RECV,
  OP_SEND,
  OP_TIMEOUT,
  OP_POLL,
  OP_ACCEPT,
  OP_CONNECT
};

typedef struct op_context {
  struct op_context *next;
  enum op_type      type: 16;
  int               completed : 16;
  int               id;
  int               result;
  VALUE             fiber;
} op_context_t;

typedef struct op_context_store {
  op_context_t *available;
  op_context_t *taken;
} op_context_store_t;

const char *op_type_to_str(enum op_type type);

void context_store_initialize(op_context_store_t *store);
op_context_t *context_store_acquire(op_context_store_t *store, enum op_type type);
void context_store_release(op_context_store_t *store, op_context_t *ctx);
void context_store_free(op_context_store_t *store);

#define OP_CONTEXT_ACQUIRE(store, op_type) context_store_acquire(store, op_type)
#define OP_CONTEXT_RELEASE(store, ctx) { \
  printf("OP_CONTEXT_RELEASE ctx %d completed: %d\n", ctx->id, ctx->completed); \
  if (ctx->completed) {\
    printf("  already completed\n"); \
    context_store_release(store, ctx); \
  } \
  else { \
    printf("  marking as completed\n"); \
    ctx->completed = 1; \
  } \
}

#endif /* BACKEND_IO_URING_CONTEXT_H */