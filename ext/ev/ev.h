#ifndef EV_H
#define EV_H

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

#endif /* EV_H */
