/*
 * Copyright (c) 2011 Tony Arcieri. Distributed under the MIT License. See
 * LICENSE.txt for further details.
 */

#ifndef NUCLEAR_H
#define NUCLEAR_H

#include "ruby.h"
#include "ruby/io.h"
#include "libev.h"

void EV_add_watcher_ref(VALUE obj);
void EV_del_watcher_ref(VALUE obj);

#ifdef GetReadFile
# define FPTR_TO_FD(fptr) (fileno(GetReadFile(fptr)))
#else
# define FPTR_TO_FD(fptr) fptr->fd
#endif /* GetReadFile */

#endif /* NUCLEAR_H */
