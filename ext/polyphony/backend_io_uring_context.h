#ifndef BACKEND_IO_URING_CONTEXT_H
#define BACKEND_IO_URING_CONTEXT_H

#include "ruby.h"

enum op_type {
  OP_NONE,
  OP_READ,
  OP_WRITEV,
  OP_WRITE,
  OP_RECV,
  OP_SEND,
  OP_SPLICE,
  OP_TIMEOUT,
  OP_POLL,
  OP_ACCEPT,
  OP_CONNECT,
  OP_CHAIN
};

typedef struct op_context {
  struct op_context *prev;
  struct op_context *next;
  enum op_type      type: 16;
  unsigned int      ref_count : 16;       
  int               id;
  int               result;
  VALUE             fiber;
  VALUE             resume_value;
  unsigned int      buffer_count;
  VALUE             buffer0;
  VALUE             *buffers;
} op_context_t;

typedef struct op_context_store {
  int           last_id;
  op_context_t  *available;
  op_context_t  *taken;
  int           available_count;
  int           taken_count;
} op_context_store_t;

const char *op_type_to_str(enum op_type type);

void context_store_initialize(op_context_store_t *store);
op_context_t *context_store_acquire(op_context_store_t *store, enum op_type type);
int context_store_release(op_context_store_t *store, op_context_t *ctx);
void context_store_free(op_context_store_t *store);
void context_store_mark_taken_buffers(op_context_store_t *store);
void context_attach_buffers(op_context_t *ctx, unsigned int count, VALUE *buffers);
void context_attach_buffers_v(op_context_t *ctx, unsigned int count, ...);

#endif /* BACKEND_IO_URING_CONTEXT_H */