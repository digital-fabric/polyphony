# frozen_string_literal: true
export_default :Commands

module Commands
  ONE = '1'
  TO_BOOL = ->(v) { v == ONE }
  TO_I_OR_NIL = ->(v) { v.nil? ? v : v.to_i }

  # https://github.com/redis/redis-rb/blob/94af6b4a78abec71b5591af0ba8fc88c8c33268a/lib/redis.rb#L277
  INFO_TRANSFORM = ->(reply) {
    reply = Hash[reply.split("\r\n").map do |line|
      line.split(":", 2) unless line =~ /^(#|$)/
    end.compact]

    # if cmd && cmd.to_s == "commandstats"
    #   # Extract nested hashes for INFO COMMANDSTATS
    #   reply = Hash[reply.map do |k, v|
    #     v = v.split(",").map { |e| e.split("=") }
    #     [k[/^cmdstat_(.*)$/, 1], Hash[v]]
    #   end]
    # end
  }

  def self.def_cmd(m, transform = nil)
    if transform
      define_method(m) { |*args| cmd(m, *args, &transform) }
    else
      define_method(m) { |*args| cmd(m, *args) }
    end
  end

  # CLUSTER
  def_cmd(:cluster)
  def_cmd(:readonly)
  def_cmd(:readwrite)

  # CONNECTION
  def_cmd(:auth)
  def_cmd(:echo)
  def_cmd(:ping)
  def_cmd(:quit)
  def_cmd(:select)
  def_cmd(:swapdb)

  # GEO
  def_cmd(:geoadd, :to_i)
  def_cmd(:geohash)
  def_cmd(:geopos)
  def_cmd(:geodist)
  def_cmd(:georadius)
  def_cmd(:georadiusbymember)

  # HASHES
  def_cmd(:hdel, :to_i)
  def_cmd(:hexists, TO_BOOL)
  def_cmd(:hget)
  def_cmd(:hgetall)
  def_cmd(:hincrby, :to_i)
  def_cmd(:hincrbyfloat, :to_f)
  def_cmd(:hkeys)
  def_cmd(:hlen, :to_i)
  def_cmd(:hmget)
  def_cmd(:hmset)
  def_cmd(:hset, TO_BOOL)
  def_cmd(:hsetnx, TO_BOOL)
  def_cmd(:hstrlen, :to_i)
  def_cmd(:hvals)
  def_cmd(:hscan)

  # HYPERLOGLOG
  def_cmd(:pfadd, TO_BOOL)
  def_cmd(:pfcount, :to_i)
  def_cmd(:pfmerge)

  # KEYS
  def_cmd(:del, :to_i)
  def_cmd(:dump)
  def_cmd(:exists)
  def_cmd(:expire, TO_BOOL)
  def_cmd(:expireat, TO_BOOL)
  def_cmd(:keys)
  def_cmd(:migrate)
  def_cmd(:move, TO_BOOL)
  def_cmd(:object)
  def_cmd(:persist, TO_BOOL)
  def_cmd(:pexpire, TO_BOOL)
  def_cmd(:pexpireat, TO_BOOL)
  def_cmd(:pttl, :to_i)
  def_cmd(:randomkey)
  def_cmd(:rename)
  def_cmd(:renamenx, TO_BOOL)
  def_cmd(:restore)
  def_cmd(:scan)
  def_cmd(:sort)
  def_cmd(:touch, :to_i)
  def_cmd(:ttl, :to_i)
  def_cmd(:type)
  def_cmd(:unlink, :to_i)
  def_cmd(:wait, :to_i)

  # LISTS
  def_cmd(:blpop)
  def_cmd(:brpop)
  def_cmd(:brpoplpush)
  def_cmd(:lindex)
  def_cmd(:linsert, :to_i)
  def_cmd(:llen, :to_i)
  def_cmd(:lpop)
  def_cmd(:lpush, :to_i)
  def_cmd(:lpushx, :to_i)
  def_cmd(:lrange)
  def_cmd(:lrem, :to_i)
  def_cmd(:lset)
  def_cmd(:ltrim)
  def_cmd(:rpop)
  def_cmd(:rpoplpush)
  def_cmd(:rpush, :to_i)
  def_cmd(:rpushx, :to_i)

  # PUB/SUB
  def_cmd(:psubscribe)
  def_cmd(:pubsub)
  def_cmd(:publish, :to_i)
  def_cmd(:punsubscribe)
  def_cmd(:subscribe)
  def_cmd(:unsubscribe)

  # SCRIPTING
  def_cmd(:eval)
  def_cmd(:evalsha)
  def_cmd(:script)

  # SERVER
  def_cmd(:bgrewriteaof)
  def_cmd(:bgsave)
  def_cmd(:client)
  def_cmd(:command)
  def_cmd(:config)
  def_cmd(:dbsize, :to_i)
  def_cmd(:debug)
  def_cmd(:flushall)
  def_cmd(:flushdb)
  def_cmd(:info, INFO_TRANSFORM)
  def_cmd(:lastsave, :to_i)
  def_cmd(:memory)
  def_cmd(:monitor)
  def_cmd(:role)
  def_cmd(:save)
  def_cmd(:shutdown)
  def_cmd(:slaveof)
  def_cmd(:slowlog)
  def_cmd(:sync)
  def_cmd(:time, ->(result) { result[0].to_f + result[1].to_f / 1e6 })

  # SETS
  def_cmd(:sadd, :to_i)
  def_cmd(:scard, :to_i)
  def_cmd(:sdiff)
  def_cmd(:sdiffstore, :to_i)
  def_cmd(:sinter)
  def_cmd(:sinterstore, :to_i)
  def_cmd(:sismember, TO_BOOL)
  def_cmd(:smembers)
  def_cmd(:smove, TO_BOOL)
  def_cmd(:spop)
  def_cmd(:srandmember)
  def_cmd(:srem, :to_i)
  def_cmd(:sunion)
  def_cmd(:sunionstore, :to_i)
  def_cmd(:sscan)

  # SORTED SETS
  def_cmd(:bzpopmin)
  def_cmd(:bzpopmax)
  def_cmd(:zadd, :to_i)
  def_cmd(:zcard, :to_i)
  def_cmd(:zcount, :to_i)
  def_cmd(:zincrby)
  def_cmd(:zinterstore, :to_i)
  def_cmd(:zlexcount, :to_i)
  def_cmd(:zpopmax)
  def_cmd(:zpopmin)
  def_cmd(:zrange)
  def_cmd(:zrangebylex)
  def_cmd(:zrevrangebylex)
  def_cmd(:zrangebyscore)
  def_cmd(:zrank, TO_I_OR_NIL)
  def_cmd(:zrem, :to_i)
  def_cmd(:zremrangebylex, :to_i)
  def_cmd(:zremrangebyrank, :to_i)
  def_cmd(:zremrangebyscore, :to_i)
  def_cmd(:zrevrange)
  def_cmd(:zrevrangebyscore)
  def_cmd(:zrevrank, TO_I_OR_NIL)
  def_cmd(:zscore)
  def_cmd(:zunionstore, :to_i)
  def_cmd(:zscan)

  # STREAMS
  def_cmd(:xadd)
  def_cmd(:xrange)
  def_cmd(:xrevrange)
  def_cmd(:xlen, :to_i)
  def_cmd(:xread)
  def_cmd(:xreadgroup)
  def_cmd(:xpending)

  # STRINGS
  def_cmd(:append, :to_i)
  def_cmd(:bitcount, :to_i)
  def_cmd(:bitfield)
  def_cmd(:bitop, :to_i)
  def_cmd(:bitpos, :to_i)
  def_cmd(:decr, :to_i)
  def_cmd(:decrby, :to_i)
  def_cmd(:get)
  def_cmd(:getbit, :to_i)
  def_cmd(:getrange)
  def_cmd(:getset)
  def_cmd(:incr, :to_i)
  def_cmd(:incrby, :to_i)
  def_cmd(:incrbyfloat, :to_f)
  def_cmd(:mget)
  def_cmd(:mset)
  def_cmd(:msetnx, TO_BOOL)
  def_cmd(:psetex)
  def_cmd(:set)
  def_cmd(:setbit, :to_i)
  def_cmd(:setex)
  def_cmd(:setnx, TO_BOOL)
  def_cmd(:setrange, :to_i)
  def_cmd(:strlen, :to_i)

  # TRANSACTIONS
  def_cmd(:discard)
  def_cmd(:exec)
  def_cmd(:multi)
  def_cmd(:unwatch)
  def_cmd(:watch)
end

