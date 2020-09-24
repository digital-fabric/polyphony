# frozen_string_literal: true

require 'rubygems'
require 'mkmf'

use_liburing = false
force_use_libev = ENV['POLYPHONY_USE_LIBEV'] != nil

if !force_use_libev && RUBY_PLATFORM =~ /linux/ && `uname -sr` =~ /Linux 5\.([\d+])/
  kernel_minor_version = $1.gsub('.', '').to_i
  use_liburing = kernel_minor_version >= 6
end

if use_liburing
  $defs << "-DPOLYPHONY_BACKEND_LIBURING"
else
  $defs << "-DPOLYPHONY_BACKEND_LIBEV"
  $defs << '-DEV_USE_LINUXAIO'     if have_header('linux/aio_abi.h')
  $defs << '-DEV_USE_SELECT'       if have_header('sys/select.h')
  $defs << '-DEV_USE_POLL'         if have_type('port_event_t', 'poll.h')
  $defs << '-DEV_USE_EPOLL'        if have_header('sys/epoll.h')
  $defs << '-DEV_USE_KQUEUE'       if have_header('sys/event.h') && have_header('sys/queue.h')
  $defs << '-DEV_USE_PORT'         if have_type('port_event_t', 'port.h')
  $defs << '-DHAVE_SYS_RESOURCE_H' if have_header('sys/resource.h')  
end

CONFIG['optflags'] << ' -fno-strict-aliasing' unless RUBY_PLATFORM =~ /mswin/

$CFLAGS << " -Wpointer-arith"

dir_config 'polyphony_ext'
create_makefile 'polyphony_ext'
