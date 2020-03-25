---
layout: page
title: Polyphony::Restart
parent: API Reference
permalink: /api-reference/polyphony-restart/
---
# Polyphony::Restart

`Polyphony::Restart` is an exception class used to restart a fiber. Applications
will not normally raise a `Polyphony::Restart` exception, but would rather use
`Fiber#restart`.

```ruby
f = spin { do_something_slow }
...
f.restart
...
```
