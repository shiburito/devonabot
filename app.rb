require 'discordrb'
require 'dotenv/load'
require 'sinatra'
require 'redis'

require_relative 'commands/favor_command'
require_relative 'commands/daily_command'
require_relative 'commands/devona_admin_command'
require_relative 'lib/redis_client_wrapper'
require_relative 'lib/wiki_client'
require_relative 'lib/twitter_feed'
require_relative 'lib/game_update_feed'
require_relative 'lib/daily_activities_feed'
server_ids = ENV.fetch('DISCORD_SERVER_IDS', "").split(',')
bot = Discordrb::Bot.new(token: ENV.fetch('DISCORD_BOT_TOKEN', nil), intents: :all)
redis_client = DevonaBot::RedisClientWrapper.new(
  url: ENV['REDIS_URL'],
  pool_size: Integer(ENV.fetch("REDIS_MAX_THREADS", 5))
)
twitter_feed_frequency_seconds = ENV['TWITTER_FEED_FREQUENCY_SECONDS']
game_updates_frequency_seconds = ENV['GAME_UPDATE_FREQUENCY_SECONDS']
daily_activities_frequency_seconds = ENV.fetch('DAILY_ACTIVITIES_FREQUENCY_SECONDS', '60').to_i

wiki_client = DevonaBot::WikiClient.new
wiki_client.login
daily_activities_feed = DevonaBot::DailyActivitiesFeed.new(bot, redis_client, wiki_client)
commands = [FavorCommand.new, DailyCommand.new(daily_activities_feed), DevonaAdminCommand.new(daily_activities_feed)]

if redis_client.call("PING") != 'PONG'
  puts("Error contacting redis, check that it's up and accessible!")
  exit 1
end

commands.each do |command|
  server_ids.each do |server_id|
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
end


commands.each do |command|
  if command.subcommands.empty?
    bot.application_command(command.id.to_sym) do |event|
      command.execute(event)
    end
  else
    command.subcommands.each do |subcommand|
      bot.application_command(command.id.to_sym).subcommand(subcommand.id.to_sym) do |event|
        subcommand.execute(event)
      end
    end
  end
end

bot.run true

twitter_feed = DevonaBot::TwitterFeed.new(bot, redis_client)
game_updates_feed = DevonaBot::GameUpdateFeed.new(bot, redis_client, wiki_client)

Thread.new do
  loop do
    begin
      twitter_feed.process
      sleep twitter_feed_frequency_seconds.to_i
    rescue => e
      puts "There was an error processing the twitter rss feed #{e}"
      sleep 2
    end
  end
end

Thread.new do
  loop do
    begin
      game_updates_feed.process
      sleep game_updates_frequency_seconds.to_i
    rescue => e
      puts "There was an error processing the game updates feed #{e}"
      sleep 2
    end
  end
end

Thread.new do
  loop do
    begin
      daily_activities_feed.process
      sleep daily_activities_frequency_seconds
    rescue => e
      puts "There was an error processing the daily activities feed #{e}"
      sleep 2
    end
  end
end

get '/' do
  'This bot serves content to the Guild Wars Global discord'
end