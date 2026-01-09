require 'discordrb'
require 'dotenv/load'
require 'sinatra'
require 'redis'

require_relative 'commands/favor_command'
require_relative 'lib/twitter_feed'

commands = [FavorCommand.new]
server_id = ENV.fetch('DISCORD_SERVER_ID', nil)
bot = Discordrb::Bot.new(token: ENV.fetch('DISCORD_BOT_TOKEN', nil), intents: :all)
redis_config = RedisClient.config(url: ENV['REDIS_URL'])
redis_client = redis_config.new_pool(timeout: 0.5, size: Integer(ENV.fetch("REDIS_MAX_THREADS", 2)))
twitter_feed_frequency_seconds = ENV['TWITTER_FEED_FREQUENCY_SECONDS']

if redis_client.call("PING") != 'PONG'
  puts("Error contacting redis, check that it's up and accessible!")
  exit 1
end

commands.each do |command|
  bot.register_application_command(command.id, command.description, server_id: server_id) do |cmd|
    if command.subcommands.empty?
      command.register(cmd)
    else
      command.subcommands.each do |subcommand|
        cmd.subcommand(subcommand.id, subcommand.description) do |sub|
          subcommand.register(sub)
        end
      end
    end
  end
end


commands.each do |command|
  if command.subcommands.empty?
    bot.application_command(command.id.to_sym) do |event|
      command.execute(event)
    end
  else
    bot.application_command(command.id.to_sym) do |app_command|
      command.subcommands.each do |subcommand|
        app_command.subcommand(subcommand.id.to_sym) do |event|
          subcommand.execute(event)
        end
      end
    end
  end
end

bot.run true

twitter_feed = DevonaBot::TwitterFeed.new(bot, redis_client)

Thread.new do
  loop do
    begin
      twitter_feed.process
      sleep(twitter_feed_frequency_seconds.to_i)
    rescue => e
      puts "There was an error processing the twitter rss feed #{e}"
      sleep(2)
    end
  end
end

get '/' do
  'Hello'
end