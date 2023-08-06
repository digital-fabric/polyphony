#include "polyphony.h"
#include "buffers.h"
#include "io_stream.h"

typedef struct io_stream {
  VALUE io;
  
  buffer_descriptor *head;
  buffer_descriptor *tail;

  buffer_descriptor *cursor_desc;
  unsigned int cursor_pos;
} IOStream_t;

VALUE cIOStream = Qnil;

static void IOStream_mark(void *ptr)
{
  IOStream_t *io_stream = ptr;
  rb_gc_mark(io_stream->io);
  buffer_descriptor *desc = io_stream->head;
  while (desc) {
    if (desc->type == BT_STRING) rb_gc_mark(desc->str);
    desc = desc->next;
  }
}

static void IOStream_free(void *ptr)
{
  xfree(ptr);
}

static size_t IOStream_size(const void *ptr)
{
  return sizeof(IOStream_t);
}

static const rb_data_type_t IOStream_type = {
  "IOStream",
  {IOStream_mark, IOStream_free, IOStream_size,},
  0, 0, 0
};

static VALUE IOStream_allocate(VALUE klass)
{
  IOStream_t *io_stream;

  io_stream = ALLOC(IOStream_t);
  return TypedData_Wrap_Struct(klass, &IOStream_type, io_stream);
}

static VALUE IOStream_initialize(VALUE self, VALUE io)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);

  io_stream->io = io;
  io_stream->head = NULL;
  io_stream->tail = NULL;
  io_stream->cursor_desc = NULL;
  io_stream->cursor_pos = 0;

  return self;
}

VALUE IOStream_left(VALUE self)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);

  int left = 0;
  buffer_descriptor *desc = io_stream->cursor_desc;
  while (desc) {
    left += desc->len;
    desc = desc->next;
  }

  return INT2FIX(left);
}

inline void io_stream_push_desc(IOStream_t *io_stream, buffer_descriptor *desc)
{
  if (io_stream->tail) {
    io_stream->tail->next = desc;
    desc->prev = io_stream->tail;
    io_stream->tail = desc;
  }
  else {
    io_stream->head = desc;
    io_stream->tail = desc;
    io_stream->cursor_desc = desc;
    io_stream->cursor_pos = 0;
    desc->prev = NULL;
    desc->next = NULL;
  }
}

VALUE IOStream_push_string(VALUE self, VALUE str)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);
  buffer_descriptor *desc;

  // do not add empty string
  if (RSTRING_LEN(str) == 0) return self;

  if (bm_buffer_from_string(&desc, str))
    rb_raise(rb_eRuntimeError, "Failed to create buffer from given string");

  io_stream_push_desc(io_stream, desc);
  return self;
}

VALUE IOStream_getbyte(VALUE self)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);

  if (!io_stream->cursor_desc)
    return Qnil;

  int byte = io_stream->cursor_desc->ptr[io_stream->cursor_pos];
  io_stream->cursor_pos++;
  if (io_stream->cursor_pos == io_stream->cursor_desc->len) {
    io_stream->cursor_desc = io_stream->cursor_desc->next;
    io_stream->cursor_pos = 0;
  }

  return INT2FIX(byte);
}

VALUE IOStream_getc(VALUE self)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);

  if (!io_stream->cursor_desc)
    return Qnil;

  // TODO: add support for multi-byte chars
  VALUE chr = rb_str_new(io_stream->cursor_desc->ptr + io_stream->cursor_pos, 1);
  io_stream->cursor_pos++;
  if (io_stream->cursor_pos == io_stream->cursor_desc->len) {
    io_stream->cursor_desc = io_stream->cursor_desc->next;
    io_stream->cursor_pos = 0;
  }

  return chr;
}

void Init_IOStream(void) {
  cIOStream = rb_define_class_under(mPolyphony, "IOStream", rb_cObject);
  rb_define_alloc_func(cIOStream, IOStream_allocate);

  rb_define_method(cIOStream, "initialize", IOStream_initialize, 1);
  rb_define_method(cIOStream, "left", IOStream_left, 0);
  rb_define_method(cIOStream, "<<", IOStream_push_string, 1);
  rb_define_method(cIOStream, "getbyte", IOStream_getbyte, 0);
  rb_define_method(cIOStream, "getc", IOStream_getc, 0);
}
