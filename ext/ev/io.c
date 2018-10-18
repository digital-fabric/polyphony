#include "ev.h"

#ifdef GetReadFile
# define FPTR_TO_FD(fptr) (fileno(GetReadFile(fptr)))
#else
# define FPTR_TO_FD(fptr) fptr->fd
#endif /* GetReadFile */

struct EV_IO {
  struct  ev_io ev_io;
  int     event_mask;
  int     active;
  int     free_in_callback;
  VALUE   callback;
  VALUE   thread;
};

static VALUE mEV = Qnil;
static VALUE cEV_IO = Qnil;

static VALUE EV_IO_allocate(VALUE klass);
static void EV_IO_mark(struct EV_IO *io);
static void EV_IO_free(struct EV_IO *io);

static VALUE EV_IO_initialize(VALUE self, VALUE io, VALUE event_mask, VALUE start);

static VALUE EV_IO_start(VALUE self);
static VALUE EV_IO_stop(VALUE self);
static VALUE EV_IO_cancel(VALUE self);

void EV_IO_callback(ev_loop *ev_loop, struct ev_io *io, int revents);

static int EV_IO_symbol2event_mask(VALUE sym);

static ID ID_call     = Qnil;
static ID ID_R        = Qnil;
static ID ID_W        = Qnil;
static ID ID_RW       = Qnil;

/* IO encapsulates an io watcher */
void Init_EV_IO() {
  mEV = rb_define_module("EV");
  cEV_IO = rb_define_class_under(mEV, "IO", rb_cObject);
  rb_define_alloc_func(cEV_IO, EV_IO_allocate);

  rb_define_method(cEV_IO, "initialize", EV_IO_initialize, 3);
  rb_define_method(cEV_IO, "start", EV_IO_start, 0);
  rb_define_method(cEV_IO, "stop", EV_IO_stop, 0);
  rb_define_method(cEV_IO, "cancel", EV_IO_cancel, 0);

  ID_call = rb_intern("call");
  ID_R = rb_intern("r");
  ID_W = rb_intern("w");
  ID_RW = rb_intern("rw");
}

static VALUE EV_IO_allocate(VALUE klass) {
  struct EV_IO *io = (struct EV_IO *)xmalloc(sizeof(struct EV_IO));

  return Data_Wrap_Struct(klass, EV_IO_mark, EV_IO_free, io);
}

static void EV_IO_mark(struct EV_IO *io) {
  if (io->callback != Qnil) {
    rb_gc_mark(io->callback);
  }
}

static void EV_IO_free(struct EV_IO *io) {
  if (rb_thread_current() != io->thread) {
    printf("thread mismatch\n");
  }
  io->free_in_callback = 1;
  ev_io_stop(EV_DEFAULT, &io->ev_io);
  return;

  if ev_is_pending(&io->ev_io) {
    io->free_in_callback = 1;
  }
  else {
    ev_io_stop(EV_DEFAULT, &io->ev_io);
    xfree(io);
  }
}

static const char * S_IO = "IO";
static const char * S_to_io = "to_io";

static VALUE EV_IO_initialize(VALUE self, VALUE io_obj, VALUE event_mask, VALUE start) {
  struct EV_IO *io;
  rb_io_t *fptr;

  Data_Get_Struct(self, struct EV_IO, io);

  io->event_mask = EV_IO_symbol2event_mask(event_mask);
  io->callback = rb_block_proc();

  GetOpenFile(rb_convert_type(io_obj, T_FILE, S_IO, S_to_io), fptr);
  ev_io_init(&io->ev_io, EV_IO_callback, FPTR_TO_FD(fptr), io->event_mask);
  
  io->active = RTEST(start);
  io->free_in_callback = 0;
  if (io->active) {
    EV_add_watcher_ref(self);
    ev_io_start(EV_DEFAULT, &io->ev_io);
  }

  io->thread = rb_thread_current();

  return Qnil;
}

/* libev callback fired on IO event */
void EV_IO_callback(ev_loop *ev_loop, struct ev_io *ev_io, int revents) {
  struct EV_IO *io = (struct EV_IO *)ev_io;

  if (io->free_in_callback) {
    printf("callback called after free\n");

    // ev_io_stop(EV_DEFAULT, ev_io);
    // xfree(io);
    return;
  }

  if (io->callback != Qnil) {
    rb_funcall(io->callback, ID_call, 1, revents);
  }
}

static VALUE EV_IO_start(VALUE self) {
  struct EV_IO *io;
  Data_Get_Struct(self, struct EV_IO, io);

  VALUE proc = rb_block_proc();
  if (proc) {
    io->callback = proc;
  }

  if (!io->active) {
    ev_io_start(EV_DEFAULT, &io->ev_io);
    io->active = 1;
    EV_add_watcher_ref(self);
  }

  return Qnil;
}

static VALUE EV_IO_stop(VALUE self) {
  struct EV_IO *io;
  Data_Get_Struct(self, struct EV_IO, io);

  if (io->active) {
    ev_io_stop(EV_DEFAULT, &io->ev_io);
    io->active = 0;
    EV_del_watcher_ref(self);
  }

  return Qnil;
}

static VALUE EV_IO_cancel(VALUE self) {
  // EV_del_watcher_ref(self);
  return EV_IO_stop(self);
}

/* Internal C functions */

static int EV_IO_symbol2event_mask(VALUE sym) {
  if (NIL_P(sym)) {
    return 0;
  }

  ID sym_id;
  sym_id = SYM2ID(sym);

  if(sym_id == ID_R) {
    return EV_READ;
  } else if(sym_id == ID_W) {
    return EV_WRITE;
  } else if(sym_id == ID_RW) {
    return EV_READ | EV_WRITE;
  } else {
    rb_raise(rb_eArgError, "invalid interest type %s (must be :r, :w, or :rw)",
      RSTRING_PTR(rb_funcall(sym, rb_intern("inspect"), 0)));
  }
}
