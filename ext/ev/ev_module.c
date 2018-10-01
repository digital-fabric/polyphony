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

/* IO encapsulates an io wsatcher */
void Init_EV()
{
    mEV = rb_define_module("EV");

    rb_define_singleton_method(mEV, "run", EV_run, 0);
    rb_define_singleton_method(mEV, "break", EV_break, 0);
    rb_define_singleton_method(mEV, "ref", EV_ref, 0);
    rb_define_singleton_method(mEV, "unref", EV_unref, 0);
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
