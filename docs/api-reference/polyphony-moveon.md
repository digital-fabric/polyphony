---
layout: page
title: Polyphony::MoveOn
parent: API Reference
permalink: /api-reference/polyphony-moveon/
---
# Polyphony::MoveOn

`Polyphony::MoveOn` is an exception class used to interrupt a blocking operation
without propagating the excception. A `Polyphony::MoveOn` exception is normally
raised using APIs such as `Fiber#interrupt` or `Object#move_on_after`. This
exception allows you to set the result of the operation being interrupted.

```ruby

def do_something_slow
  sleep 10
  'foo'
end

f = spin { do_something_slow }
f.interrupt('bar')
f.await #=> 'bar'
```
