---
layout: page
title: ::Exception
parent: API Reference
permalink: /api-reference/exception/
---
# ::Exception

[Ruby core Exception documentation](https://ruby-doc.org/core-2.7.0/Exception.html)

The core `Exception` class is enhanced to provide a better backtrace that takes
into account the fiber hierarchy. In addition, a `source_fiber` attribute allows
tracking the fiber from which an uncaught exception was propagated.

## Class Methods

## Instance methods

### #source_fiber → fiber

Returns the fiber in which the exception occurred. Polyphony sets this attribute
only for uncaught exceptions. Currently this attribute is only used in a
meaningful way for supervising fibers.

### #source_fiber=(fiber) → fiber

Sets the fiber in which the exception occurred.