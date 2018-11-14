# frozen_string_literal: true

export_default :Commands

# Redis commands
module Commands
end

ONE = '1'
NEWLINE = '\r\n'
COLON = ':'
HASHDOLLAR = /^(#|$)/

TO_I = :to_i.to_proc
TO_F = :to_f.to_proc
TO_BOOL = ->(v) { v == ONE }
TO_I_OR_NIL = ->(v) { v.nil? ? v : v.to_i }

# https://github.com/redis/redis-rb/blob/94af6b4a78abec71b5591af0ba8fc88c8c33268a/lib/redis.rb#L277
INFO_TRANSFORM = lambda do |reply|
  Hash[reply.split(NEWLINE).map do |line|
    line.split(COLON, 2) unless line =~ HASHDOLLAR
  end.compact]
end

{
  # CLUSTER
  cluster:            nil,
  readonly:           nil,
  readwrite:          nil,

  # CONNECTION
  auth:               nil,
  echo:               nil,
  ping:               nil,
  quit:               nil,
  select:             nil,
  swapdb:             nil,

  # GEO
  geoadd:             TO_I,
  geohash:            nil,
  geopos:             nil,
  geodist:            nil,
  georadius:          nil,
  georadiusbymember:  nil,

  # HASHES
  hdel:               TO_I,
  hexists:            TO_BOOL,
  hget:               nil,
  hgetall:            nil,
  hincrby:            TO_I,
  hincrbyfloat:       TO_F,
  hkeys:              nil,
  hlen:               TO_I,
  hmget:              nil,
  hmset:              nil,
  hset:               TO_BOOL,
  hsetnx:             TO_BOOL,
  hstrlen:            TO_I,
  hvals:              nil,
  hscan:              nil,

  # HYPERLOGLOG
  pfadd:              TO_BOOL,
  pfcount:            TO_I,
  pfmerge:            nil,

  # KEYS
  del:                TO_I,
  dump:               nil,
  exists:             TO_BOOL,
  expire:             TO_BOOL,
  expireat:           TO_BOOL,
  keys:               nil,
  migrate:            nil,
  move:               TO_BOOL,
  object:             nil,
  persist:            TO_BOOL,
  pexpire:            TO_BOOL,
  pexpireat:          TO_BOOL,
  pttl:               TO_I,
  randomkey:          nil,
  rename:             nil,
  renamenx:           TO_BOOL,
  restore:            nil,
  scan:               nil,
  sort:               nil,
  touch:              TO_I,
  ttl:                TO_I,
  type:               nil,
  unlink:             TO_I,
  wait:               TO_I,

  # LISTS
  blpop:              nil,
  brpop:              nil,
  brpoplpush:         nil,
  lindex:             nil,
  linsert:            TO_I,
  llen:               TO_I,
  lpop:               nil,
  lpush:              TO_I,
  lpushx:             TO_I,
  lrange:             nil,
  lrem:               TO_I,
  lset:               nil,
  ltrim:              nil,
  rpop:               nil,
  rpoplpush:          nil,
  rpush:              TO_I,
  rpushx:             TO_I,

  # PUB/SUB
  psubscribe:         nil,
  pubsub:             nil,
  publish:            TO_I,
  punsubscribe:       nil,
  subscribe:          nil,
  unsubscribe:        nil,

  # SCRIPTING
  eval:               nil,
  evalsha:            nil,
  script:             nil,

  # SERVER
  bgrewriteaof:       nil,
  bgsave:             nil,
  client:             nil,
  command:            nil,
  config:             nil,
  dbsize:             TO_I,
  debug:              nil,
  flushall:           nil,
  flushdb:            nil,
  info:               INFO_TRANSFORM,
  lastsave:           TO_I,
  memory:             nil,
  monitor:            nil,
  role:               nil,
  save:               nil,
  shutdown:           nil,
  slaveof:            nil,
  slowlog:            nil,
  sync:               nil,
  time: ->(result) { result[0].to_f + result[1].to_f / 1e6 },

  # SETS
  sadd:               TO_I,
  scard:              TO_I,
  sdiff:              nil,
  sdiffstore:         TO_I,
  sinter:             nil,
  sinterstore:        TO_I,
  sismember:          TO_BOOL,
  smembers:           nil,
  smove:              TO_BOOL,
  spop:               nil,
  srandmember:        nil,
  srem:               TO_I,
  sunion:             nil,
  sunionstore:        TO_I,
  sscan:              nil,

  # SORTED SETS
  bzpopmin:           nil,
  bzpopmax:           nil,
  zadd:               TO_I,
  zcard:              TO_I,
  zcount:             TO_I,
  zincrby:            nil,
  zinterstore:        TO_I,
  zlexcount:          TO_I,
  zpopmax:            nil,
  zpopmin:            nil,
  zrange:             nil,
  zrangebylex:        nil,
  zrevrangebylex:     nil,
  zrangebyscore:      nil,
  zrank:              TO_I_OR_NIL,
  zrem:               TO_I,
  zremrangebylex:     TO_I,
  zremrangebyrank:    TO_I,
  zremrangebyscore:   TO_I,
  zrevrange:          nil,
  zrevrangebyscore:   nil,
  zrevrank:           TO_I_OR_NIL,
  zscore:             nil,
  zunionstore:        TO_I,
  zscan:              nil,

  # STREAMS
  xadd:               nil,
  xrange:             nil,
  xrevrange:          nil,
  xlen:               TO_I,
  xread:              nil,
  xreadgroup:         nil,
  xpending:           nil,

  # STRINGS
  append:             TO_I,
  bitcount:           TO_I,
  bitfield:           nil,
  bitop:              TO_I,
  bitpos:             TO_I,
  decr:               TO_I,
  decrby:             TO_I,
  get:                nil,
  getbit:             TO_I,
  getrange:           nil,
  getset:             nil,
  incr:               TO_I,
  incrby:             TO_I,
  incrbyfloat:        TO_F,
  mget:               nil,
  mset:               nil,
  msetnx:             TO_BOOL,
  psetex:             nil,
  set:                nil,
  setbit:             TO_I,
  setex:              nil,
  setnx:              TO_BOOL,
  setrange:           TO_I,
  strlen:             TO_I,

  # TRANSACTIONS
  discard:            nil,
  exec:               nil,
  multi:              nil,
  unwatch:            nil,
  watch:              nil
}.each do |sym, transform|
  if transform
    Commands.define_method(sym) { |*args| cmd(sym, *args, &transform) }
  else
    Commands.define_method(sym) { |*args| cmd(sym, *args) }
  end
end
