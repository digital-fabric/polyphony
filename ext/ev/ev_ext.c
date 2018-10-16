#include "ev.h"
#include "../libev/ev.c"

void Init_EV();
void Init_EV_IO();
void Init_EV_Timer();
void Init_EV_Signal();
void Init_EV_Async();

void Init_ev_ext() {
  ev_set_allocator(xrealloc);

  Init_EV();
  Init_EV_IO();
  Init_EV_Timer();
  Init_EV_Signal();
  Init_EV_Async();
}
