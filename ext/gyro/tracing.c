#include "gyro.h"

int __tracing_enabled__ = 0;

VALUE __fiber_trace__(int argc, VALUE *argv, VALUE self) {
  return rb_ary_new4(argc, argv);
}

void Init_Tracing() {
  rb_define_global_function("__fiber_trace__", __fiber_trace__, -1);
}