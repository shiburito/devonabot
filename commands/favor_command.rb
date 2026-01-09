# frozen_string_literal: true
require_relative '../lib/discord_command'

class FavorCommand < DevonaBot::Commands::DiscordCommand
  def initialize
    super("favor", "favor", "Tells you how long is left on favor")
  end

  def register(sub)

  end
  def execute(event)
    event.respond(content: "This doesn't currently do anything.", ephemeral: true)
  end
end
