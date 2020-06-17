#include "polyphony.h"

void Init_Fiber();
void Init_Polyphony();
void Init_LibevAgent();
void Init_Queue();
void Init_Socket();
void Init_Thread();
void Init_Tracing();

void Init_polyphony_ext() {
  ev_set_allocator(xrealloc);

  Init_Polyphony();
  Init_LibevAgent();
  Init_Queue();

  Init_Fiber();
  Init_Socket();
  Init_Thread();

  Init_Tracing();
}