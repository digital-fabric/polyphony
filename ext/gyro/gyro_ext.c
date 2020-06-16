#include "gyro.h"

void Init_Fiber();
void Init_Gyro();
void Init_LibevAgent();
void Init_Gyro_Queue();
void Init_Socket();
void Init_Thread();
void Init_Tracing();

void Init_gyro_ext() {
  ev_set_allocator(xrealloc);

  Init_Gyro();
  Init_LibevAgent();
  Init_Gyro_Queue();

  Init_Fiber();
  Init_Socket();
  Init_Thread();

  Init_Tracing();
}