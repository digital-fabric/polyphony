#include "polyphony.h"
#include "runqueue.h"

inline void runqueue_initialize(runqueue_t *runqueue) {
  runqueue_ring_buffer_init(&runqueue->entries);
  runqueue->high_watermark = 0;
}

inline void runqueue_finalize(runqueue_t *runqueue) {
  runqueue_ring_buffer_free(&runqueue->entries);
}

inline void runqueue_mark(runqueue_t *runqueue) {
  runqueue_ring_buffer_mark(&runqueue->entries);
}

inline void runqueue_push(runqueue_t *runqueue, VALUE fiber, VALUE value, int reschedule) {
  if (reschedule) {
    int idx = runqueue_ring_buffer_index_of(&runqueue->entries, fiber);
    
    // check if the fiber is the last entry
    if (idx == runqueue->entries.count - 1) {
      // if it is, we can simply update the resume value, no need to do all that
      // work for nothing.
      runqueue_ring_buffer_set_resume_value_at(&runqueue->entries, idx, value);
      return;
    }
    
    runqueue_ring_buffer_delete_at(&runqueue->entries, idx);
  }
  runqueue_ring_buffer_push(&runqueue->entries, fiber, value);
  if (runqueue->entries.count > runqueue->high_watermark)
    runqueue->high_watermark = runqueue->entries.count;
}

inline void runqueue_unshift(runqueue_t *runqueue, VALUE fiber, VALUE value, int reschedule) {
  if (reschedule) runqueue_ring_buffer_delete(&runqueue->entries, fiber);
  runqueue_ring_buffer_unshift(&runqueue->entries, fiber, value);
  if (runqueue->entries.count > runqueue->high_watermark)
    runqueue->high_watermark = runqueue->entries.count;
}

inline runqueue_entry runqueue_shift(runqueue_t *runqueue) {
  return runqueue_ring_buffer_shift(&runqueue->entries);
}

inline void runqueue_delete(runqueue_t *runqueue, VALUE fiber) {
  runqueue_ring_buffer_delete(&runqueue->entries, fiber);
}

inline int runqueue_index_of(runqueue_t *runqueue, VALUE fiber) {
  return runqueue_ring_buffer_index_of(&runqueue->entries, fiber);
}

inline void runqueue_migrate(runqueue_t *src, runqueue_t *dest, VALUE fiber) {
  runqueue_ring_buffer_migrate(&src->entries, &dest->entries, fiber);
}

inline void runqueue_clear(runqueue_t *runqueue) {
  runqueue_ring_buffer_clear(&runqueue->entries);
}

inline unsigned int runqueue_size(runqueue_t *runqueue) {
  return runqueue->entries.size;
}

inline unsigned int runqueue_len(runqueue_t *runqueue) {
  return runqueue->entries.count;
}

inline unsigned int runqueue_max_len(runqueue_t *runqueue) {
  unsigned int max_len = runqueue->high_watermark;
  runqueue->high_watermark = 0;
  return max_len;
}

inline int runqueue_empty_p(runqueue_t *runqueue) {
  return (runqueue->entries.count == 0);
}
