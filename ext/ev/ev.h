#ifndef RUBY_EV_H
#define RUBY_EV_H

#include "ruby.h"
#include "ruby/io.h"
#include "libev.h"

void EV_add_watcher_ref(VALUE obj);
void EV_del_watcher_ref(VALUE obj);
void EV_async_free(void *p);

#define SCHEDULE_FIBER(obj, args...) rb_funcall(obj, ID_transfer, args)
#define YIELD_TO_REACTOR() rb_funcall(EV_reactor_fiber, ID_transfer, 0)

#endif /* RUBY_EV_H */
