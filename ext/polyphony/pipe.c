#include <unistd.h>
#include "polyphony.h"

typedef struct pipe {
  int fds[2];
  unsigned int w_closed;
} Pipe_t;

VALUE cPipe = Qnil;
VALUE cClosedPipeError = Qnil;

static void Pipe_free(void *ptr) {
  Pipe_t *pipe = ptr;
  close(pipe->fds[0]);
  if (!pipe->w_closed) close(pipe->fds[1]);
  xfree(ptr);
}

static size_t Pipe_size(const void *ptr) {
  return sizeof(Pipe_t);
}

static const rb_data_type_t Pipe_type = {
  "Pipe",
  {NULL, Pipe_free, Pipe_size,},
  0, 0, 0
};

static VALUE Pipe_allocate(VALUE klass) {
  Pipe_t *pipe;

  pipe = ALLOC(Pipe_t);
  return TypedData_Wrap_Struct(klass, &Pipe_type, pipe);
}

#define GetPipe(obj, pipe) \
  TypedData_Get_Struct((obj), Pipe_t, &Pipe_type, (pipe))

static VALUE Pipe_initialize(int argc, VALUE *argv, VALUE self) {
  Pipe_t *pipe_struct;
  GetPipe(self, pipe_struct);

  int ret = pipe(pipe_struct->fds);
  if (ret) {
    int e = errno;
    rb_syserr_fail(e, strerror(e));
  }
  pipe_struct->w_closed = 0;

  return self;
}

void Pipe_verify_blocking_mode(VALUE self, VALUE blocking) {
  Pipe_t *pipe_struct;
  VALUE blocking_mode = rb_ivar_get(self, ID_ivar_blocking_mode);
  if (blocking == blocking_mode) return;

  rb_ivar_set(self, ID_ivar_blocking_mode, blocking);
  GetPipe(self, pipe_struct);

  set_fd_blocking_mode(pipe_struct->fds[0], blocking == Qtrue);
  set_fd_blocking_mode(pipe_struct->fds[1], blocking == Qtrue);
}

int Pipe_get_fd(VALUE self, int write_mode) {
  Pipe_t *pipe;
  GetPipe(self, pipe);

  if (write_mode && pipe->w_closed)
    rb_raise(cClosedPipeError, "Pipe is closed for writing");

  return pipe->fds[write_mode ? 1 : 0];
}

VALUE Pipe_closed_p(VALUE self) {
  Pipe_t *pipe;
  GetPipe(self, pipe);
  return pipe->w_closed ? Qtrue : Qfalse;
}

VALUE Pipe_close(VALUE self) {
  Pipe_t *pipe;
  GetPipe(self, pipe);
  if (pipe->w_closed)
    rb_raise(rb_eRuntimeError, "Pipe is already closed for writing");

  pipe->w_closed = 1;
  close(pipe->fds[1]);
  return self;
}

VALUE Pipe_fds(VALUE self) {
  Pipe_t *pipe;
  GetPipe(self, pipe);

  return rb_ary_new_from_args(2, INT2FIX(pipe->fds[0]), INT2FIX(pipe->fds[1]));
}

void Init_Pipe() {
  cPipe = rb_define_class_under(mPolyphony, "Pipe", rb_cObject);
  cClosedPipeError = rb_define_class_under(cPipe, "ClosedPipeError", rb_eRuntimeError);

  rb_define_alloc_func(cPipe, Pipe_allocate);

  rb_define_method(cPipe, "initialize", Pipe_initialize, -1);
  rb_define_method(cPipe, "closed?", Pipe_closed_p, 0);
  rb_define_method(cPipe, "close", Pipe_close, 0);
  rb_define_method(cPipe, "fds", Pipe_fds, 0);
}
