#include "polyphony.h"

void Init_Fiber();
void Init_Polyphony();
void Init_LibevBackend();
void Init_Queue();
void Init_Event();
void Init_Thread();
void Init_Tracing();

void Init_polyphony_ext() {
  ev_set_allocator(xrealloc);

  Init_Polyphony();

  Init_LibevBackend();
  Init_Queue();
  Init_Event();
  Init_Fiber();
  Init_Thread();
  Init_Tracing();
}