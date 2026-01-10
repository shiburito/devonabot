require 'rss'
require 'discordrb'

module DevonaBot
  class TwitterFeed

    TWITTER_USER = 'GuildWars'

    def initialize(discord_bot, redis_client)
      @discord_bot = discord_bot
      @redis_client = redis_client
      @feed = RSS::Parser.parse(ENV['TWITTER_FEED'])
      @links_to_post = []
      @channels = ENV['TWITTER_DISCORD_CHANNELS'].split(',')
      @processing = false
    end

    def process
      return if @processing
      @processing = true
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

        existing_entry = @redis_client.call("EXISTS", post_id)
        next if existing_entry == 1

        @links_to_post << data
      end

      @channels.each do |channel|
        @links_to_post.reverse.each do |data|
          puts "Posting tweet #{data['link']} to #{channel}"
          @discord_bot.send_message(channel, data['link'])
          store_tweet(data)
          sleep 2
        end
      end
      @processing = false
    end

    def store_tweet(tweet)
      @redis_client.call("HSET", tweet['id'], *tweet.flatten)
    end

  end
end