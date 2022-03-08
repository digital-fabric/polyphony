#include "polyphony.h"

void Init_Polyphony();
void Init_Backend();
void Init_Pipe();
void Init_Queue();
void Init_Event();
void Init_Fiber();
void Init_Thread();

void Init_IOExtensions();
void Init_SocketExtensions();

#ifdef POLYPHONY_PLAYGROUND
extern void playground();
#endif

void Init_polyphony_ext() {
  Init_Polyphony();

  Init_Backend();
  Init_Queue();
  Init_Pipe();
  Init_Event();
  Init_Fiber();
  Init_Thread();

  Init_IOExtensions();
  Init_SocketExtensions();

  #ifdef POLYPHONY_PLAYGROUND
  playground();
  #endif
}