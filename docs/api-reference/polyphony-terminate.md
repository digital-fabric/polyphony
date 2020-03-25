---
layout: page
title: Polyphony::Terminate
parent: API Reference
permalink: /api-reference/polyphony-terminate/
---
# Polyphony::Terminate

`Polyphony::Terminate` is an exception class used to terminate a fiber without
propagating the exception. It should never be rescued. A `Polyphony::Terminate`
exception is normally raised using APIs such as `Fiber#terminate` or
`Fiber#terminate_all_children`.

```ruby
f = spin { do_something_slow }
...
f.terminate
```
