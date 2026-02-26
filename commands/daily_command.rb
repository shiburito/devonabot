# frozen_string_literal: true
require_relative '../lib/discord_command'

class DailyCommand < DevonaBot::Commands::DiscordCommand
  def initialize(feed)
    super("daily", "daily", "Show today's Guild Wars daily activities")
    @feed = feed
  end

  def register(sub)
  end

  def execute(event)
    embed = @feed.get_today_embed

    if embed
      event.respond(embeds: [embed.to_hash], ephemeral: true)
    else
      event.respond(content: "Could not fetch today's daily activities. Try again later.", ephemeral: true)
    end
  end
end
