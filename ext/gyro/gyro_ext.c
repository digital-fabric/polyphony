#include "gyro.h"

void Init_Gyro();
void Init_Gyro_Async();
void Init_Gyro_Child();
void Init_Gyro_IO();
void Init_Gyro_Signal();
void Init_Gyro_Timer();
void Init_Socket();

void Init_gyro_ext() {
  ev_set_allocator(xrealloc);

  Init_Gyro();
  Init_Gyro_Async();
  Init_Gyro_Child();
  Init_Gyro_IO();
  Init_Gyro_Signal();
  Init_Gyro_Timer();

  Init_Socket();
}