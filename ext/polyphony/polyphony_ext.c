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

void Init_polyphony_ext(void) {
  printf("Init_polyphony_ext 1\n");
  Init_Polyphony();

  printf("Init_polyphony_ext 2\n");
  Init_Backend();
  printf("Init_polyphony_ext 3\n");
  Init_Queue();
  printf("Init_polyphony_ext 4\n");
  Init_Pipe();
  Init_Event();
  Init_Fiber();
  Init_Thread();

  printf("Init_polyphony_ext 5\n");
  Init_IOExtensions();
  Init_SocketExtensions();
  printf("Init_polyphony_ext 6\n");

  #ifdef POLYPHONY_PLAYGROUND
  playground();
  #endif
}