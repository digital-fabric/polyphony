#ifndef RUNQUEUE_H
#define RUNQUEUE_H

#include "polyphony.h"
#include "runqueue_ring_buffer.h"

typedef struct runqueue {
  runqueue_ring_buffer entries;
  unsigned int high_watermark;
} runqueue_t;

void runqueue_initialize(runqueue_t *runqueue);
void runqueue_finalize(runqueue_t *runqueue);
void runqueue_mark(runqueue_t *runqueue);

void runqueue_push(runqueue_t *runqueue, VALUE fiber, VALUE value, int reschedule);
void runqueue_unshift(runqueue_t *runqueue, VALUE fiber, VALUE value, int reschedule);
runqueue_entry runqueue_shift(runqueue_t *runqueue);
void runqueue_delete(runqueue_t *runqueue, VALUE fiber);
int runqueue_index_of(runqueue_t *runqueue, VALUE fiber);
void runqueue_clear(runqueue_t *runqueue);
long runqueue_size(runqueue_t *runqueue);
long runqueue_len(runqueue_t *runqueue);
long runqueue_max_len(runqueue_t *runqueue);
int runqueue_empty_p(runqueue_t *runqueue);

#endif /* RUNQUEUE_H */