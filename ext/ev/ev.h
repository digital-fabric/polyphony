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

extern VALUE EV_reactor_fiber;
extern VALUE EV_root_fiber;

extern ID ID_call;
extern ID ID_caller;
extern ID ID_clear;
extern ID ID_each;
extern ID ID_inspect;
extern ID ID_raise;
extern ID ID_read_watcher;
extern ID ID_scheduled_value;
extern ID ID_transfer;
extern ID ID_write_watcher;
extern ID ID_R;
extern ID ID_W;
extern ID ID_RW;

#endif /* RUBY_EV_H */
