---
layout: page
title: Polyphony::Cancel
parent: API Reference
permalink: /api-reference/polyphony-cancel/
---
# Polyphony::Cancel

`Polyphony::Cancel` is an exception class used to interrupt a blocking operation
with an exception that must be rescued. This exception is will propagate if not
rescued. A `Polyphony::Cancel` exception is normally raised using APIs such as
`Fiber#cancel!` or `Object#cancel_after`.

```ruby
require 'httparty'
require 'time'

def current_server_time
  cancel_after(10) do
    response_body = HTTParty.get(TIME_URL).body
    Time.parse(response_body)
  end
rescue Polyphony::Cancel
  Time.now
end
```
