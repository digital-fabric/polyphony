# frozen_string_literal: true

require 'rubygems'
require 'mkmf'

use_liburing = false
use_pidfd_open = false
force_use_libev = ENV['POLYPHONY_USE_LIBEV'] != nil
linux = RUBY_PLATFORM =~ /linux/

if linux && `uname -sr` =~ /Linux 5\.([\d+])/
  kernel_minor_version = $1.gsub('.', '').to_i
  use_liburing = !force_use_libev && kernel_minor_version >= 6
  use_pidfd_open = kernel_minor_version >= 3
end

$defs << '-DPOLYPHONY_USE_PIDFD_OPEN' if use_pidfd_open
if use_liburing
  $defs << "-DPOLYPHONY_BACKEND_LIBURING"
  $defs << "-DPOLYPHONY_UNSET_NONBLOCK" if RUBY_VERSION =~ /^3/
  $CFLAGS << " -Wno-pointer-arith"
else
  $defs << "-DPOLYPHONY_BACKEND_LIBEV"
  $defs << "-DPOLYPHONY_LINUX" if linux
  $defs << '-DEV_USE_LINUXAIO'     if have_header('linux/aio_abi.h')
  $defs << '-DEV_USE_SELECT'       if have_header('sys/select.h')
  $defs << '-DEV_USE_POLL'         if have_type('port_event_t', 'poll.h')
  $defs << '-DEV_USE_EPOLL'        if have_header('sys/epoll.h')
  $defs << '-DEV_USE_KQUEUE'       if have_header('sys/event.h') && have_header('sys/queue.h')
  $defs << '-DEV_USE_PORT'         if have_type('port_event_t', 'port.h')
  $defs << '-DHAVE_SYS_RESOURCE_H' if have_header('sys/resource.h')  

  $CFLAGS << " -Wno-comment"
  $CFLAGS << " -Wno-unused-result"
  $CFLAGS << " -Wno-dangling-else"
  $CFLAGS << " -Wno-parentheses"
end

$defs << '-DPOLYPHONY_PLAYGROUND' if ENV['POLYPHONY_PLAYGROUND']

CONFIG['optflags'] << ' -fno-strict-aliasing' unless RUBY_PLATFORM =~ /mswin/


dir_config 'polyphony_ext'
create_makefile 'polyphony_ext'
