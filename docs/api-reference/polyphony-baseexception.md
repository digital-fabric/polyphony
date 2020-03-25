---
layout: page
title: Polyphony::BaseException
parent: API Reference
permalink: /api-reference/polyphony-baseexception/
---
# Polyphony::BaseException

The `Polyphony::BaseException` is a common base class for exceptions used to
control fiber execution. Instances of descendant classes are meant to be created
explicitly using `new`, e.g. `Polyphony::MoveOn.new`, rather than using `raise
Polyphony::MoveOn`. Normally an application will not use those classes directly
but would rather use APIs such as `Fiber#interrupt`.

## Derived classes

- [`Polyphony::Cancel`](../polyphony-cancel/)
- [`Polyphony::MoveOn`](../polyphony-moveon/)
- [`Polyphony::Restart`](../polyphony-restart/)
- [`Polyphony::Terminate`](../polyphony-terminate/)

## Instance methods

### #initialize(value = nil)

Initializes the exception with an optional result value. The value will be used
as the result of the block being interrupted or the fiber being terminated.

```ruby
f = spin { 'foo' }
f.raise(Polyphony::Terminate.new('bar'))
f.await #=> 'bar'
```