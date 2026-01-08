require 'discordrb'
require 'dotenv/load'
require 'sinatra'

require_relative 'commands/favor_command'

server_id = ENV.fetch('DISCORD_SERVER_ID', nil)
bot = Discordrb::Bot.new(token: ENV.fetch('DISCORD_BOT_TOKEN', nil), intents: :all)
commands = [FavorCommand.new]

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

get '/' do
  'Hello'
end