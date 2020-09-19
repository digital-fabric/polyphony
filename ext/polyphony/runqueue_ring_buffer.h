#ifndef RUNQUEUE_RING_BUFFER_H
#define RUNQUEUE_RING_BUFFER_H

#include "ruby.h"

typedef struct runqueue_entry {
  VALUE fiber;
  VALUE value;
} runqueue_entry;

typedef struct runqueue_ring_buffer {
  runqueue_entry *entries;
  unsigned int size;
  unsigned int count;
  unsigned int head;
  unsigned int tail;
} runqueue_ring_buffer;

void runqueue_ring_buffer_init(runqueue_ring_buffer *buffer);
void runqueue_ring_buffer_free(runqueue_ring_buffer *buffer);
void runqueue_ring_buffer_mark(runqueue_ring_buffer *buffer);
int runqueue_ring_buffer_empty_p(runqueue_ring_buffer *buffer);
void runqueue_ring_buffer_clear(runqueue_ring_buffer *buffer);

runqueue_entry runqueue_ring_buffer_shift(runqueue_ring_buffer *buffer);
void runqueue_ring_buffer_unshift(runqueue_ring_buffer *buffer, VALUE fiber, VALUE value);
void runqueue_ring_buffer_push(runqueue_ring_buffer *buffer, VALUE fiber, VALUE value);

void runqueue_ring_buffer_delete(runqueue_ring_buffer *buffer, VALUE fiber);

#endif /* RUNQUEUE_RING_BUFFER_H */