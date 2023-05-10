#include "polyphony.h"

VALUE mPolyphony;
VALUE cTimeoutException;

ID ID_call;
ID ID_caller;
ID ID_clear;
ID ID_each;
ID ID_inspect;
ID ID_invoke;
ID ID_ivar_blocking_mode;
ID ID_ivar_io;
ID ID_ivar_multishot_accept_queue;
ID ID_ivar_parked;
ID ID_ivar_runnable;
ID ID_ivar_running;
ID ID_ivar_thread;
ID ID_new;
ID ID_raise;
ID ID_size;
ID ID_signal;
ID ID_switch_fiber;
ID ID_to_s;
ID ID_transfer;
ID ID_R;
ID ID_W;
ID ID_RW;

/* Switches to the next fiber in the current thread's runqueue after adding the
 * current fiber to the runqueue. This lets other fibers run, letting the
 * current fiber eventually continue its work. This call is useful when
 * performing long-running calculations in order to keep the program responsive.
 * 
 * @return [void]
 */

VALUE Polyphony_snooze(VALUE self) {
  return Backend_snooze(BACKEND());
}

/* Switches to the next fiber in the current thread's runqueue without
 * rescheduling the current fiber. This is useful if the current fiber does not
 * need to continue or will be scheduled by other means eventually.
 * 
 * @return [void]
 */

static VALUE Polyphony_suspend(VALUE self) {
  VALUE ret = Thread_switch_fiber(rb_thread_current());

  RAISE_IF_EXCEPTION(ret);
  RB_GC_GUARD(ret);
  return ret;
}

/* Accepts an incoming connection on the given server socket, returning an
 * instance of the given socket class.
 * 
 * @param server_socket [Socket] socket to accept on
 * @param socket_class [Class] class of the socket to instantiate for the accepted connection
 * 
 * @return [Socket] accepted connection
 */

VALUE Polyphony_backend_accept(VALUE self, VALUE server_socket, VALUE socket_class) {
  return Backend_accept(BACKEND(), server_socket, socket_class);
}

/* Runs an infinite loop accepting connections on the given server socket,
 * returning an instance of the given socket class.
 * 
 * @param server_socket [Socket] socket to accept on
 * @param socket_class [Class] class of the socket to instantiate for the accepted connection
 * @yield [Socket] accepted connection
 * @return [void]
 */

VALUE Polyphony_backend_accept_loop(VALUE self, VALUE server_socket, VALUE socket_class) {
  return Backend_accept_loop(BACKEND(), server_socket, socket_class);
}

#ifdef HAVE_IO_URING_PREP_MULTISHOT_ACCEPT
/* Starts a multishot accept operation on the given server socket. This API is
 * available only for the io_uring backend.
 * 
 * @param server_socket [Socket] socket to accept on
 * @return [void]
 */

VALUE Polyphony_backend_multishot_accept(VALUE self, VALUE server_socket) {
  return Backend_multishot_accept(BACKEND(), server_socket);
}
#endif


/* Connects the given socket to the given address and port.
 * 
 * @param io [Socket] socket to connect
 * @param addr [String] address to connect to
 * @param port [Integer] port to connect to
 * 
 * @return [Socket] accepted connection
 */

VALUE Polyphony_backend_connect(VALUE self, VALUE io, VALUE addr, VALUE port) {
  return Backend_connect(BACKEND(), io, addr, port);
}

/* Runs a feed loop, reading data from the given io, feeding it to the receiver
 * with the given method. The loop terminates when EOF is encountered. If a
 * block is given, it is used as the block for the method call to the receiver.
 *
 * @param io [IO] io to read from
 * @param receiver [any] an object receiving the data
 * @param method [Symbol] method used to feed the data to the receiver
 *
 * @return [IO] io
 */

VALUE Polyphony_backend_feed_loop(VALUE self, VALUE io, VALUE receiver, VALUE method) {
  return Backend_feed_loop(BACKEND(), io, receiver, method);
}

/* Reads from the given io.
 * 
 * @param io [IO] io to read from
 * @param buffer [String, nil] buffer to read into
 * @param length [Integer] maximum bytes to read
 * @param to_eof [boolean] whether to read to EOF
 * @param pos [Integer] Position in the buffer to read into
 * 
 * @return [String] buffer
 */

VALUE Polyphony_backend_read(VALUE self, VALUE io, VALUE buffer, VALUE length, VALUE to_eof, VALUE pos) {
  return Backend_read(BACKEND(), io, buffer, length, to_eof, pos);
}

/* Performs an infinite loop reading data from the given io. The loop terminates
 * when EOF is encountered.
 * 
 * @param io [IO] io to read from
 * @param maxlen [Integer] maximum bytes to read
 * 
 * @return [void]
 */

VALUE Polyphony_backend_read_loop(VALUE self, VALUE io, VALUE maxlen) {
  return Backend_read_loop(BACKEND(), io, maxlen);
}

/* Receives data on the given io.
 * 
 * @param io [Socket] io to receive on
 * @param buffer [String, nil] buffer to read into
 * @param length [Integer] maximum bytes to read
 * @param pos [Integer] Position in the buffer to read into
 * 
 * @return [String] buffer
 */

VALUE Polyphony_backend_recv(VALUE self, VALUE io, VALUE buffer, VALUE length, VALUE pos) {
  return Backend_recv(BACKEND(), io, buffer, length, pos);
}

/* Receives a message on the given socket.
 * 
 * @param socket [UDPSocket] io to receive on
 * @param buffer [String, nil] buffer to read into
 * @param maxlen [Integer] maximum bytes to read
 * @param pos [Integer] Position in the buffer to read into
 * @param flags [Integer] Flags
 * @param maxcontrollen [Integer] Maximum control bytes
 * @param opts [Hash] Options
 * @return [String] buffer
 */

VALUE Polyphony_backend_recvmsg(VALUE self, VALUE socket, VALUE buffer, VALUE maxlen, VALUE pos, VALUE flags, VALUE maxcontrollen, VALUE opts) {
  return Backend_recvmsg(BACKEND(), socket, buffer, maxlen, pos, flags, maxcontrollen, opts);
}

/* Performs an infinite loop receiving data on the given socket. The loop
 * terminates when the socket is closed.
 * 
 * @param socket [Socket] socket to receive on
 * @param maxlen [Integer] maximum bytes to read
 * @yield [data] received data
 * @return [void]
 */

VALUE Polyphony_backend_recv_loop(VALUE self, VALUE socket, VALUE maxlen) {
  return Backend_recv_loop(BACKEND(), socket, maxlen);
}

/* Runs a feed loop, receiving data on the given socket, feeding it to the
 * receiver with the given method. The loop terminates when EOF is encountered.
 * If a block is given, it is used as the block for the method call to the
 * receiver.
 * 
 * @param socket [Socket] socket to receive on
 * @param receiver [any] an object receiving the data
 * @param method [Symbol] method used to feed the data to the receiver
 * 
 * @return [void]
 */

VALUE Polyphony_backend_recv_feed_loop(VALUE self, VALUE socket, VALUE receiver, VALUE method) {
  return Backend_recv_feed_loop(BACKEND(), socket, receiver, method);
}

/* Sends data on the given socket, returning the number of bytes sent.
 * 
 * @param socket [Socket] socket to read from
 * @param msg [String] data to be sent
 * @param flags [Integer] Flags
 * 
 * @return [Integer] number of bytes sent
 */

VALUE Polyphony_backend_send(VALUE self, VALUE socket, VALUE msg, VALUE flags) {
  return Backend_send(BACKEND(), socket, msg, flags);
}

/* Sends data on the given socket, returning the number of bytes sent.
 * 
 * @param socket [Socket] socket to read from
 * @param msg [String] data to be sent
 * @param flags [Integer] Flags
 * @param dest_sockaddr [any] Destination address
 * @param controls [any] Control data
 * @return [Integer] number of bytes sent
 */

VALUE Polyphony_backend_sendmsg(VALUE self, VALUE socket, VALUE msg, VALUE flags, VALUE dest_sockaddr, VALUE controls) {
  return Backend_sendmsg(BACKEND(), socket, msg, flags, dest_sockaddr, controls);
}

/* Sends multiple strings on the given socket, returning the number of bytes
 * sent.
 * 
 * @param socket [Socket] socket to read from
 * @param ary [Array<String>] data to be sent
 * @param flags [Integer] Flags
 * @return [Integer] number of bytes sent
 */

VALUE Polyphony_backend_sendv(VALUE self, VALUE socket, VALUE ary, VALUE flags) {
  return Backend_sendv(BACKEND(), socket, ary, flags);
}

/* Sleeps for the given duration, yielding execution to other fibers.
 * 
 * @param duration [Number] duration in seconds
 * @return [void]
 */

VALUE Polyphony_backend_sleep(VALUE self, VALUE duration) {
  return Backend_sleep(BACKEND(), duration);
}

/* Splices data from the given source to the given destination, returning the
 * number of bytes spliced.
 * 
 * @param src [IO] source
 * @param dest [IO] destination
 * @param maxlen [Integer] Maximum bytes to splice
 * @return [Integer] number of bytes spliced
 */

VALUE Polyphony_backend_splice(VALUE self, VALUE src, VALUE dest, VALUE maxlen) {
  return Backend_splice(BACKEND(), src, dest, maxlen);
}

#ifdef POLYPHONY_BACKEND_LIBURING
/* @!visibility private */

VALUE Polyphony_backend_double_splice(VALUE self, VALUE src, VALUE dest) {
  return Backend_double_splice(BACKEND(), src, dest);
}
#endif

#ifdef POLYPHONY_LINUX
/* @!visibility private */

VALUE Polyphony_backend_tee(VALUE self, VALUE src, VALUE dest, VALUE chunksize) {
  return Backend_tee(BACKEND(), src, dest, chunksize);
}
#endif

/* Runs the given block, raising an exception if the block has not finished
 * running before a timeout has elapsed, using the given duration. If an
 * exception class is not given, a TimeoutError is raised.
 * 
 * @overload backend_timeout(duration)
 *   @param duration [Number] timeout duration in seconds
 *   @return [any] return value of block
 * @overload backend_timeout(duration, exception_class)
 *   @param duration [Number] timeout duration in seconds
 *   @param exception_class [Class] exception class to raise in case of timeout
 *   @return [any] return value of block
 */

VALUE Polyphony_backend_timeout(int argc,VALUE *argv, VALUE self) {
  return Backend_timeout(argc, argv, BACKEND());
}

/* Runs an infinite loop that calls the given block at the specified time interval.
 * 
 * @param interval [Number] interval in seconds
 * @return [void]
 */

VALUE Polyphony_backend_timer_loop(VALUE self, VALUE interval) {
  return Backend_timer_loop(BACKEND(), interval);
}

/* For for the current fiber to be rescheduled, resuming the fiber with its
 * resumed value. If raise is true and the resumed value is an exception, an
 * exception will be raised.
 * 
 * @param raise [boolean]
 * @return [any] resumed value
 */

VALUE Polyphony_backend_wait_event(VALUE self, VALUE raise) {
  return Backend_wait_event(BACKEND(), raise);
}

/* Waits for the given IO to be readable or writeable, according to the
 * read_or_write parameter.
 * 
 * @param io [IO]
 * @param write [boolean] false for read, true for write
 * @return [void]
 */

VALUE Polyphony_backend_wait_io(VALUE self, VALUE io, VALUE write) {
  return Backend_wait_io(BACKEND(), io, write);
}

/* Waits for the given process to terminate, returning its exit code.
 * 
 * @param pid [Integer] pid
 * @return [Integer] exit code
 */

VALUE Polyphony_backend_waitpid(VALUE self, VALUE pid) {
  return Backend_waitpid(BACKEND(), pid);
}

/* Writes one or more strings to the given io, returning the total number of
 * bytes written.
 */

VALUE Polyphony_backend_write(int argc, VALUE *argv, VALUE self) {
  return Backend_write_m(argc, argv, BACKEND());
}

/* @!visibility private */

VALUE Polyphony_with_raw_buffer(VALUE self, VALUE size) {
  struct buffer_spec buffer_spec;
  buffer_spec.len = FIX2INT(size);
  buffer_spec.ptr = malloc(buffer_spec.len);
  if (!buffer_spec.ptr)
    rb_raise(rb_eRuntimeError, "Failed to allocate buffer");

  VALUE return_value = rb_yield(PTR2FIX(&buffer_spec));
  free(buffer_spec.ptr);
  return return_value;
}

/* @!visibility private */

VALUE Polyphony_raw_buffer_get(int argc, VALUE *argv, VALUE self) {
  VALUE buf = Qnil;
  VALUE len = Qnil;
  rb_scan_args(argc, argv, "11", &buf, &len);

  struct buffer_spec *buffer_spec = FIX2PTR(buf);
  int length = (len == Qnil) ? buffer_spec->len : FIX2INT(len);
  
  if (length > buffer_spec->len) length = buffer_spec->len;
  return rb_utf8_str_new((char *)buffer_spec->ptr, length);
}

/* @!visibility private */

VALUE Polyphony_raw_buffer_set(VALUE self, VALUE buffer, VALUE str) {
  struct buffer_spec *buffer_spec = FIX2PTR(buffer);
  int len = RSTRING_LEN(str);
  if (len > buffer_spec->len)
    rb_raise(rb_eRuntimeError, "Given string does not fit in given buffer");
  
  memcpy(buffer_spec->ptr, RSTRING_PTR(str), len);
  buffer_spec->len = len;
  return self;
}

/* @!visibility private */

VALUE Polyphony_raw_buffer_size(VALUE self, VALUE buffer) {
  struct buffer_spec *buffer_spec = FIX2PTR(buffer);
  return INT2FIX(buffer_spec->len);
}

// VALUE Polyphony_backend_close(VALUE self, VALUE io) {
//   return Backend_close(BACKEND(), io);
// }

void Init_Polyphony(void) {
  mPolyphony = rb_define_module("Polyphony");

  // backend methods
  rb_define_singleton_method(mPolyphony, "backend_accept", Polyphony_backend_accept, 2);
  rb_define_singleton_method(mPolyphony, "backend_accept_loop", Polyphony_backend_accept_loop, 2);
  rb_define_singleton_method(mPolyphony, "backend_connect", Polyphony_backend_connect, 3);
  rb_define_singleton_method(mPolyphony, "backend_feed_loop", Polyphony_backend_feed_loop, 3);

  #ifdef HAVE_IO_URING_PREP_MULTISHOT_ACCEPT
  rb_define_singleton_method(mPolyphony, "backend_multishot_accept", Polyphony_backend_multishot_accept, 1);
  #endif


  rb_define_singleton_method(mPolyphony, "backend_read", Polyphony_backend_read, 5);
  rb_define_singleton_method(mPolyphony, "backend_read_loop", Polyphony_backend_read_loop, 2);
  rb_define_singleton_method(mPolyphony, "backend_recv", Polyphony_backend_recv, 4);
  rb_define_singleton_method(mPolyphony, "backend_recvmsg", Polyphony_backend_recvmsg, 7);
  rb_define_singleton_method(mPolyphony, "backend_recv_loop", Polyphony_backend_recv_loop, 2);
  rb_define_singleton_method(mPolyphony, "backend_recv_feed_loop", Polyphony_backend_recv_feed_loop, 3);
  rb_define_singleton_method(mPolyphony, "backend_send", Polyphony_backend_send, 3);
  rb_define_singleton_method(mPolyphony, "backend_sendmsg", Polyphony_backend_sendmsg, 5);
  rb_define_singleton_method(mPolyphony, "backend_sendv", Polyphony_backend_sendv, 3);
  rb_define_singleton_method(mPolyphony, "backend_sleep", Polyphony_backend_sleep, 1);
  rb_define_singleton_method(mPolyphony, "backend_splice", Polyphony_backend_splice, 3);
 
  #ifdef POLYPHONY_BACKEND_LIBURING
  rb_define_singleton_method(mPolyphony, "backend_double_splice", Polyphony_backend_double_splice, 2);
  #endif

  #ifdef POLYPHONY_LINUX
  rb_define_singleton_method(mPolyphony, "backend_tee", Polyphony_backend_tee, 3);
  #endif
  
  rb_define_singleton_method(mPolyphony, "backend_timeout", Polyphony_backend_timeout, -1);
  rb_define_singleton_method(mPolyphony, "backend_timer_loop", Polyphony_backend_timer_loop, 1);
  rb_define_singleton_method(mPolyphony, "backend_wait_event", Polyphony_backend_wait_event, 1);
  rb_define_singleton_method(mPolyphony, "backend_wait_io", Polyphony_backend_wait_io, 2);
  rb_define_singleton_method(mPolyphony, "backend_waitpid", Polyphony_backend_waitpid, 1);
  rb_define_singleton_method(mPolyphony, "backend_write", Polyphony_backend_write, -1);
  // rb_define_singleton_method(mPolyphony, "backend_close", Polyphony_backend_close, 1);
  rb_define_singleton_method(mPolyphony, "backend_verify_blocking_mode", Backend_verify_blocking_mode, 2);

  rb_define_singleton_method(mPolyphony, "__with_raw_buffer__", Polyphony_with_raw_buffer, 1);
  rb_define_singleton_method(mPolyphony, "__raw_buffer_get__", Polyphony_raw_buffer_get, -1);
  rb_define_singleton_method(mPolyphony, "__raw_buffer_set__", Polyphony_raw_buffer_set, 2);
  rb_define_singleton_method(mPolyphony, "__raw_buffer_size__", Polyphony_raw_buffer_size, 1);

  rb_define_global_function("snooze", Polyphony_snooze, 0);
  rb_define_global_function("suspend", Polyphony_suspend, 0);

  /*
   * Document-class: Polyphony::TimeoutException
   *
   * An exception raised on timeout.
   */

  cTimeoutException = rb_define_class_under(mPolyphony, "TimeoutException", rb_eException);

  ID_call                         = rb_intern("call");
  ID_caller                       = rb_intern("caller");
  ID_clear                        = rb_intern("clear");
  ID_each                         = rb_intern("each");
  ID_inspect                      = rb_intern("inspect");
  ID_invoke                       = rb_intern("invoke");
  ID_ivar_blocking_mode           = rb_intern("@blocking_mode");
  ID_ivar_io                      = rb_intern("@io");
  ID_ivar_multishot_accept_queue  = rb_intern("@multishot_accept_queue");
  ID_ivar_parked                  = rb_intern("@parked");
  ID_ivar_runnable                = rb_intern("@runnable");
  ID_ivar_running                 = rb_intern("@running");
  ID_ivar_thread                  = rb_intern("@thread");
  ID_new                          = rb_intern("new");
  ID_raise                        = rb_intern("raise");
  ID_signal                       = rb_intern("signal");
  ID_size                         = rb_intern("size");
  ID_switch_fiber                 = rb_intern("switch_fiber");
  ID_to_s                         = rb_intern("to_s");
  ID_transfer                     = rb_intern("transfer");
}