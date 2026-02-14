require 'rss'
require 'discordrb'

module DevonaBot
  class TwitterFeed

    TWITTER_USER = 'GuildWars'

    def initialize(discord_bot, redis_client)
      @discord_bot = discord_bot
      @redis_client = redis_client
      @feed = RSS::Parser.parse(ENV['TWITTER_FEED'])
      @links_to_post = {}
      @channels = ENV['TWITTER_DISCORD_CHANNELS'].split(',')
      @processing = false
      @disable_messages = ENV['DISABLE_MESSAGES'] == 'true'

      @channels.each do |channel|
        @links_to_post[channel] = []
      end
    end

    def process
      return if @processing
      @processing = true
      puts 'Fetching twitter feed...'
      @channels.each do |channel|
        @feed.items.each do |item|
          post_id = item.link.split('/').last.gsub('#m','')
          link = "https://x.com/GuildWars/status/#{post_id}"
          data = {
            "id" => post_id,
            "title" => item.title.to_s,
            "link" => link,
            "description" => item.description.to_s,
            "pub_date" => item.pubDate.to_s,
          }

          existing_entry = @redis_client.call("EXISTS", "tweet:#{channel}:#{post_id}")
          next unless existing_entry == 0

          @links_to_post[channel] = [] unless @links_to_post[channel]
          @links_to_post[channel] << data
        end
      end



      @channels.each do |channel|
        puts "Found #{@links_to_post[channel].size} tweets to post for channel #{channel}" if @links_to_post[channel].size > 0
        @links_to_post[channel].reverse.each do |data|
          if @disable_messages
            puts "Would post tweet #{data['link']} to #{channel} but in debug mode"
          else
            puts "Posting tweet #{data['link']} to #{channel}"
            @discord_bot.send_message(channel, data['link'])
            store_tweet(channel, data)
          end
          sleep 2
        end
      end
      @processing = false
    end

    def store_tweet(channel, tweet)
      @redis_client.call("HSET", "tweet:#{channel}:#{tweet['id']}", *tweet.flatten)
    end

  end
end