#include <time.h>

#include "polyphony.h"
#include "zlib.h"
#include "assert.h"

ID ID_read_method;
ID ID_write_method;

enum read_method {
  RM_BACKEND_READ,
  RM_BACKEND_RECV
};

enum write_method {
  WM_BACKEND_WRITE,
  WM_BACKEND_SEND
};

#define CHUNK 16384
#define MAX_WRITE_STR_LEN 16384
#define DEFAULT_LEVEL 9

inline int read_to_raw_buffer(VALUE backend, VALUE io, enum read_method method, struct raw_buffer *buffer) {
  VALUE len = Backend_read(backend, io, PTR2FIX(buffer), Qnil, Qfalse, INT2FIX(0));
  return (len == Qnil) ? 0 : FIX2INT(len);
}

inline int write_from_raw_buffer(VALUE backend, VALUE io, enum write_method method, struct raw_buffer *buffer) {
  VALUE len = Backend_write(backend, io, PTR2FIX(buffer));
  return FIX2INT(len);
}

static inline int write_c_string_from_str(VALUE str, struct raw_buffer *buffer) {
  int strlen = RSTRING_LEN(str);
  if (strlen >= buffer->len)
    rb_raise(rb_eRuntimeError, "string too long to fit in gzip header buffer");

  memcpy(buffer->ptr, RSTRING_PTR(str), strlen);
  buffer->ptr[strlen] = 0;
  int written = strlen + 1;
  buffer->ptr += written;
  buffer->len -= written;
  return written;
}

struct gzip_header_ctx {
  int os_code;        /* for header */
  time_t mtime;       /* for header */
  VALUE orig_name;    /* for header; must be a String */
  VALUE comment;      /* for header; must be a String */
  unsigned long crc;
};

#define GZ_MAGIC1             0x1f
#define GZ_MAGIC2             0x8b
#define GZ_METHOD_DEFLATE     8
#define GZ_FLAG_MULTIPART     0x2
#define GZ_FLAG_EXTRA         0x4
#define GZ_FLAG_ORIG_NAME     0x8
#define GZ_FLAG_COMMENT       0x10
#define GZ_FLAG_ENCRYPT       0x20
#define GZ_FLAG_UNKNOWN_MASK  0xc0

#define GZ_EXTRAFLAG_FAST     0x4
#define GZ_EXTRAFLAG_SLOW     0x2

#define ZSTREAM_FLAG_READY      (1 << 0)
#define ZSTREAM_FLAG_IN_STREAM  (1 << 1)
#define ZSTREAM_FLAG_FINISHED   (1 << 2)
#define ZSTREAM_FLAG_CLOSING    (1 << 3)
#define ZSTREAM_FLAG_GZFILE     (1 << 4) /* disallows yield from expand_buffer for
                                        gzip*/
#define ZSTREAM_REUSE_BUFFER    (1 << 5)
#define ZSTREAM_IN_PROGRESS     (1 << 6)
#define ZSTREAM_FLAG_UNUSED     (1 << 7)

#define ZSTREAM_READY(z)       ((z)->flags |= ZSTREAM_FLAG_READY)
#define ZSTREAM_IS_READY(z)    ((z)->flags & ZSTREAM_FLAG_READY)
#define ZSTREAM_IS_FINISHED(z) ((z)->flags & ZSTREAM_FLAG_FINISHED)
#define ZSTREAM_IS_CLOSING(z)  ((z)->flags & ZSTREAM_FLAG_CLOSING)
#define ZSTREAM_IS_GZFILE(z)   ((z)->flags & ZSTREAM_FLAG_GZFILE)
#define ZSTREAM_BUF_FILLED(z)  (NIL_P((z)->buf) ? 0 : RSTRING_LEN((z)->buf))

#define GZFILE_FLAG_SYNC             ZSTREAM_FLAG_UNUSED
#define GZFILE_FLAG_HEADER_FINISHED  (ZSTREAM_FLAG_UNUSED << 1)
#define GZFILE_FLAG_FOOTER_FINISHED  (ZSTREAM_FLAG_UNUSED << 2)
#define GZFILE_FLAG_MTIME_IS_SET     (ZSTREAM_FLAG_UNUSED << 3)

static void gzfile_set32(unsigned long n, unsigned char *dst) {
  *(dst++) = n & 0xff;
  *(dst++) = (n >> 8) & 0xff;
  *(dst++) = (n >> 16) & 0xff;
  *dst     = (n >> 24) & 0xff;
}

int gzip_write_header(struct gzip_header_ctx *ctx, char *buffer, int maxlen) {
  int len = 0;
  unsigned char flags = 0, extraflags = 0;

  assert(maxlen >= 10);

  if (!NIL_P(ctx->orig_name)) {
	  flags |= GZ_FLAG_ORIG_NAME;
  }
  if (!NIL_P(ctx->comment)) {
	  flags |= GZ_FLAG_COMMENT;
  }
  // if (!(ctx->z.flags & GZFILE_FLAG_MTIME_IS_SET)) {
	//   ctx->mtime = time(0);
  // }

  // if (ctx->level == Z_BEST_SPEED) {
	//   extraflags |= GZ_EXTRAFLAG_FAST;
  // }
  // else if (ctx->level == Z_BEST_COMPRESSION) {
	//   extraflags |= GZ_EXTRAFLAG_SLOW;
  // }


  buffer[0] = GZ_MAGIC1;
  buffer[1] = GZ_MAGIC2;
  buffer[2] = GZ_METHOD_DEFLATE;
  buffer[3] = flags;
  gzfile_set32((unsigned long)ctx->mtime, &buffer[4]);
  buffer[8] = extraflags;
  buffer[9] = ctx->os_code;

  len = 10;

  struct raw_buffer buffer_spec = {buffer + len, maxlen - len};
  if (!NIL_P(ctx->orig_name))
    len += write_c_string_from_str(ctx->orig_name, &buffer_spec);
  if (!NIL_P(ctx->comment))
    len += write_c_string_from_str(ctx->comment, &buffer_spec);

  return len;
}

int gzip_write_footer(ulong crc32, ulong total_in, char *buffer, int maxlen) {
  assert(maxlen >= 8);

  gzfile_set32(crc32, buffer);
  gzfile_set32(total_in, buffer + 4);

  return 8;
}

/******************************************************************************/

enum stream_mode {
  SM_DEFLATE,
  SM_INFLATE
};

struct z_stream_ctx {
  VALUE backend;
  VALUE src;
  VALUE dest;
  z_stream strm;
  int starting_pos;
  unsigned char in[CHUNK];
  unsigned char out[CHUNK];

  enum stream_mode mode;
  ulong crc32;
  ulong read_total;
  ulong write_total;
};

void z_stream_io_loop(struct z_stream_ctx *ctx) {
  int pos = ctx->starting_pos;
  int (*fun)(z_streamp, int) = (ctx->mode == SM_DEFLATE) ? deflate : inflate;
  int ret;
  int avail_out_pre;
  
  struct raw_buffer in_buffer = {ctx->in, CHUNK};
  struct raw_buffer out_buffer = {ctx->out, CHUNK};


  while (1) {
    ctx->strm.next_in = ctx->in;
    ctx->strm.avail_in = read_to_raw_buffer(ctx->backend, ctx->src, RM_BACKEND_READ, &in_buffer);
    if (!ctx->strm.avail_in) break;

    ctx->read_total += ctx->strm.avail_in;

    while (1) {
      avail_out_pre = ctx->strm.avail_out = CHUNK - pos;
      ctx->strm.next_out = ctx->out + pos;
      ret = fun(&ctx->strm, Z_PARTIAL_FLUSH); /* no bad return value */
      assert(ret != Z_STREAM_ERROR);
      int written = avail_out_pre - ctx->strm.avail_out;

      out_buffer.len = pos + written;
      ret = write_from_raw_buffer(ctx->backend, ctx->dest, WM_BACKEND_WRITE, &out_buffer);
      printf("write %d => %d\n", out_buffer.len, ret);
      ctx->write_total += ret - pos;
      assert(ret == pos + written);
      pos = 0;

      // if there's still room in the out buffer that means the input buffer has been exhausted
      if (ctx->strm.avail_out) break;
    }
  }

  //flush
  ctx->strm.avail_in = 0;
  ctx->strm.next_in = ctx->in;
  avail_out_pre = ctx->strm.avail_out = CHUNK - pos;
  ctx->strm.next_out = ctx->out + pos;
  ret = fun(&ctx->strm, Z_FINISH); /* no bad return value */
  assert(ret != Z_STREAM_ERROR);
  int written = avail_out_pre - ctx->strm.avail_out;
  
  out_buffer.len = pos + written;
  if (out_buffer.len) {
    ret = write_from_raw_buffer(ctx->backend, ctx->dest, WM_BACKEND_WRITE, &out_buffer);
    ctx->write_total += ret - pos;
    printf("write (flush) %d => %d\n", out_buffer.len, ret);
  }
}

/* from zutil.h */
#define OS_MSDOS    0x00
#define OS_AMIGA    0x01
#define OS_VMS      0x02
#define OS_UNIX     0x03
#define OS_ATARI    0x05
#define OS_OS2      0x06
#define OS_MACOS    0x07
#define OS_TOPS20   0x0a
#define OS_WIN32    0x0b

#define OS_VMCMS    0x04
#define OS_ZSYSTEM  0x08
#define OS_CPM      0x09
#define OS_QDOS     0x0c
#define OS_RISCOS   0x0d
#define OS_UNKNOWN  0xff

#ifndef OS_CODE
#define OS_CODE  OS_UNIX
#endif

VALUE IO_gzip(VALUE self, VALUE src, VALUE dest) {
  struct gzip_header_ctx header_ctx = {
    OS_CODE,
    0,
    Qnil,
    Qnil,
    0
  };

  struct z_stream_ctx ctx;
  int level = DEFAULT_LEVEL;
  int ret;

  ctx.backend = BACKEND();
  ctx.src = src;
  ctx.dest = dest;
  ctx.strm.zalloc = Z_NULL;
  ctx.strm.zfree = Z_NULL;
  ctx.strm.opaque = Z_NULL;

  ctx.starting_pos = gzip_write_header(&header_ctx, ctx.out, sizeof(ctx.out));

  ctx.mode = SM_DEFLATE;
  ctx.crc32 = 0;
  ctx.read_total = 0;
  ctx.write_total = 0;

  ret = deflateInit(&ctx.strm, level);
  if (ret != Z_OK) return INT2FIX(ret);

  z_stream_io_loop(&ctx);

  int footer_len = gzip_write_footer(ctx.crc32, ctx.read_total, ctx.out, sizeof(ctx.out));
  printf("footer_len read_total: %ld, write_total: %ld\n", ctx.read_total, ctx.write_total);
  struct raw_buffer footer_buffer = {ctx.out, footer_len};
  write_from_raw_buffer(ctx.backend, dest, WM_BACKEND_WRITE, &footer_buffer);

  deflateEnd(&ctx.strm);
 
  return self;
}

VALUE IO_gunzip(VALUE self, VALUE src, VALUE dest) {
  return self;
}

VALUE IO_deflate(VALUE self, VALUE src, VALUE dest) {
  struct z_stream_ctx ctx;
  int level = DEFAULT_LEVEL;
  int ret;

  ctx.backend = BACKEND();
  ctx.src = src;
  ctx.dest = dest;
  ctx.strm.zalloc = Z_NULL;
  ctx.strm.zfree = Z_NULL;
  ctx.strm.opaque = Z_NULL;
  ctx.starting_pos = 0;
  ctx.mode = SM_DEFLATE;
  ret = deflateInit(&ctx.strm, level);
  if (ret != Z_OK) return INT2FIX(ret);

  z_stream_io_loop(&ctx);

  deflateEnd(&ctx.strm);
 
  return self;
}

VALUE IO_inflate(VALUE self, VALUE src, VALUE dest) {
  struct z_stream_ctx ctx;

  ctx.backend = BACKEND();
  ctx.src = src;
  ctx.dest = dest;
  ctx.strm.zalloc = Z_NULL;
  ctx.strm.zfree = Z_NULL;
  ctx.strm.opaque = Z_NULL;
  ctx.starting_pos = 0;
  ctx.mode = SM_INFLATE;
  int ret = inflateInit(&ctx.strm);
  if (ret != Z_OK) return INT2FIX(ret);

  z_stream_io_loop(&ctx);

  inflateEnd(&ctx.strm);
 
  return self;
}

void Init_IOExtensions() {
  // mPolyphony = rb_define_module("Polyphony");

  rb_define_singleton_method(rb_cIO, "gzip", IO_gzip, 2);
  rb_define_singleton_method(rb_cIO, "gunzip", IO_gunzip, 2);
  rb_define_singleton_method(rb_cIO, "deflate", IO_deflate, 2);
  rb_define_singleton_method(rb_cIO, "inflate", IO_inflate, 2);

  ID_read_method =  rb_intern("__read_method__");
  ID_write_method = rb_intern("__write_method__");
}
