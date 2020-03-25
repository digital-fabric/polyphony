---
layout: page
title: Polyphony::ResourcePool
parent: API Reference
permalink: /api-reference/polyphony-resourcepool/
---
# Polyphony::ResourcePool

`Polyphony::ResourcePool` implements a general purpose resource pool for
limiting concurrent access to a resource or multiple copies thereof. A resource
pool might be used for example to limit the number of concurrent database
connections.

## Class methods

## Instance methods

### #acquire({ block })

Acquires a resource and passes it to the given block. The resource will be used
exclusively by the given block, and then returned to the pool. This method
blocks until the given block has completed running. If no resource is available,
this method blocks until a resource has been released.

```ruby
db_connections = Polyphony::ResourcePool.new(limit: 5) { PG.connect(opts) }

def query_records(sql)
  db_connections.acquire do |db|
    db.query(sql).to_a
  end
end
```

### #available → count

Returns the number of resources currently available in the resource pool.

### #initialize(limit: number, { block })

Initializes a new resource pool with the given maximum number of concurrent
resources. The given block is used to create the resource.

```ruby
require 'postgres'

opts = { host: '/tmp', user: 'admin', dbname: 'mydb' }
db_connections = Polyphony::ResourcePool.new(limit: 5) { PG.connect(opts) }
```

### #limit → count

Returns the size limit of the resource pool.

### #size → count

Returns the total number of allocated resources in the resource pool. This
includes both available and unavailable resources.

