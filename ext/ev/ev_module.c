/*
 * Copyright (c) 2011 Tony Arcieri. Distributed under the MIT License. See
 * LICENSE.txt for further details.
 */

#include "ev.h"

static VALUE mEV = Qnil;

static VALUE EV_run(VALUE self);
static VALUE EV_break(VALUE self);

static VALUE EV_ref(VALUE self);
static VALUE EV_unref(VALUE self);

void EV_init_watcher_hash();

static VALUE watcher_refs;

/* IO encapsulates an io wsatcher */
void Init_EV()
{
    mEV = rb_define_module("EV");

    rb_define_singleton_method(mEV, "run", EV_run, 0);
    rb_define_singleton_method(mEV, "break", EV_break, 0);
    rb_define_singleton_method(mEV, "ref", EV_ref, 0);
    rb_define_singleton_method(mEV, "unref", EV_unref, 0);

    watcher_refs = rb_hash_new();
    rb_ivar_set(mEV, rb_intern("__watcher_refs"), watcher_refs);
}

static VALUE EV_run(VALUE self)
{
    ev_run (EV_DEFAULT, 0);

    return Qnil;
}

static VALUE EV_break(VALUE self)
{
    ev_break (EV_DEFAULT, EVBREAK_ALL);

    return Qnil;
}

static VALUE EV_ref(VALUE self)
{
    ev_ref (EV_DEFAULT);

    return Qnil;
}

static VALUE EV_unref(VALUE self)
{
    ev_unref (EV_DEFAULT);

    return Qnil;
}

void EV_add_watcher_ref(VALUE obj) {
  rb_hash_aset(watcher_refs, rb_obj_id(obj), obj);
}

void EV_del_watcher_ref(VALUE obj) {
  rb_hash_delete(watcher_refs, rb_obj_id(obj));
}
