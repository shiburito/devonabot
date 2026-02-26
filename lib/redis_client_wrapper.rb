require 'redis'

module DevonaBot
  class RedisClientWrapper
    MAX_RETRIES = 3

    def initialize(url:, connect_timeout: 5.0, read_timeout: 5.0, write_timeout: 5.0, pool_timeout: 5.0, pool_size: 5)
      config = RedisClient.config(
        url: url,
        connect_timeout: connect_timeout,
        read_timeout: read_timeout,
        write_timeout: write_timeout
      )
      @pool = config.new_pool(timeout: pool_timeout, size: pool_size)
      @debug = ENV['DEBUG'] == 'true'
    end

    def call(*args)
      retries = 0
      begin
        @pool.call(*args)
      rescue RedisClient::TimeoutError, RedisClient::ConnectionError => e
        retries += 1
        if retries <= MAX_RETRIES
          puts "Redis #{args.first} failed (attempt #{retries}/#{MAX_RETRIES}): #{e.message}, retrying..." if @debug
          sleep 1
          retry
        end
        raise
      end
    end
  end
end
