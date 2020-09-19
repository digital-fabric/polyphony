#include "polyphony.h"

void Init_Fiber();
void Init_Polyphony();
void Init_Backend();
void Init_Queue();
void Init_Event();
void Init_Runqueue();
void Init_Thread();
void Init_Tracing();

void Init_polyphony_ext() {
  Init_Polyphony();

  Init_Backend();
  Init_Queue();
  Init_Event();
  Init_Runqueue();
  Init_Fiber();
  Init_Thread();
  Init_Tracing();
}