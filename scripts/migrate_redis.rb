require 'redis-client'

source = RedisClient.config(url: ENV.fetch('SOURCE_REDIS_URL', 'redis://redis:6379')).new_client
target = RedisClient.config(url: ENV.fetch('TARGET_REDIS_URL')).new_client

migrated = 0
cursor = "0"

loop do
  cursor, keys = source.call("SCAN", cursor, "COUNT", 100)
  keys.each do |key|
    type = source.call("TYPE", key)

    case type
    when "string"
      val = source.call("GET", key)
      target.call("SET", key, val)
    when "hash"
      data = source.call("HGETALL", key)
      target.call("HSET", key, *data.flatten) unless data.empty?
    when "list"
      vals = source.call("LRANGE", key, 0, -1)
      target.call("RPUSH", key, *vals) unless vals.empty?
    when "set"
      vals = source.call("SMEMBERS", key)
      target.call("SADD", key, *vals) unless vals.empty?
    when "zset"
      vals = source.call("ZRANGE", key, 0, -1, "WITHSCORES")
      args = vals.each_slice(2).flat_map { |member, score| [score, member] }
      target.call("ZADD", key, *args) unless args.empty?
    else
      puts "Skipping key '#{key}' with unsupported type '#{type}'"
      next
    end

    ttl = source.call("PTTL", key)
    target.call("PEXPIRE", key, ttl) if ttl > 0

    migrated += 1
    puts "Migrated #{type} key: #{key}"
  end
  break if cursor == "0"
end

puts "Done. Migrated #{migrated} keys."
