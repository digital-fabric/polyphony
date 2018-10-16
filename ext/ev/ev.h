#ifndef RUBY_EV_H
#define RUBY_EV_H

#include "ruby.h"
#include "ruby/io.h"
#include "libev.h"

void EV_add_watcher_ref(VALUE obj);
void EV_del_watcher_ref(VALUE obj);
void EV_async_free(void *p);

static ID ID_call;
static ID ID_each;

#endif /* RUBY_EV_H */
