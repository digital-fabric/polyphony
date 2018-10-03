/*
 * Copyright (c) 2011 Tony Arcieri. Distributed under the MIT License. See
 * LICENSE.txt for further details.
 */

#ifndef NUCLEAR_H
#define NUCLEAR_H

#include "ruby.h"
#include "ruby/io.h"
#include "libev.h"

struct EV_Timer
{
    VALUE self;
    struct ev_timer ev_timer;
    VALUE callback;
};

struct EV_Signal
{
    VALUE self;
    int signum;
    struct ev_signal ev_signal;
    VALUE callback;
};

struct EV_Async
{
    VALUE self;
    struct ev_async ev_async;
    VALUE callback;
};

#ifdef GetReadFile
# define FPTR_TO_FD(fptr) (fileno(GetReadFile(fptr)))
#else
# define FPTR_TO_FD(fptr) fptr->fd
#endif /* GetReadFile */

#endif /* NUCLEAR_H */
