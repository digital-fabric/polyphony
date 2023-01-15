#include "polyphony.h"

VALUE Socket_send(VALUE self, VALUE msg, VALUE flags) {
  return Backend_send(BACKEND(), self, msg, flags);
}

VALUE Socket_write(int argc, VALUE *argv, VALUE self) {
  VALUE ary = rb_ary_new_from_values(argc, argv);
  VALUE result = Backend_sendv(BACKEND(), self, ary, INT2FIX(0));
  RB_GC_GUARD(ary);
  return result;
}

VALUE Socket_double_chevron(VALUE self, VALUE msg) {
  Backend_send(BACKEND(), self, msg, INT2FIX(0));
  return self;
}

void Init_SocketExtensions(void) {
  VALUE cSocket;
  VALUE cTCPSocket;

  rb_require("socket");

  cSocket = rb_const_get(rb_cObject, rb_intern("Socket"));
  cTCPSocket = rb_const_get(rb_cObject, rb_intern("TCPSocket"));

  rb_define_method(cSocket, "send", Socket_send, 2);
  rb_define_method(cTCPSocket, "send", Socket_send, 2);

  rb_define_method(cSocket, "write", Socket_write, -1);
  rb_define_method(cTCPSocket, "write", Socket_write, -1);

  rb_define_method(cSocket, "<<", Socket_double_chevron, 1);
  rb_define_method(cTCPSocket, "<<", Socket_double_chevron, 1);
}
