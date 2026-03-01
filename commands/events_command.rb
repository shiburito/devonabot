# frozen_string_literal: true
require_relative '../lib/discord_command'

class EventsCommand < DevonaBot::Commands::DiscordCommand
  def initialize(feed)
    super("events", "events", "Show upcoming Guild Wars special events")
    @feed = feed
  end

  def register(sub)
  end

  def execute(event)
    embed = @feed.get_current_embed

    if embed
      event.respond(embeds: [embed.to_hash], ephemeral: true)
    else
      event.respond(content: "Could not fetch upcoming special events. Try again later.", ephemeral: true)
    end
  end
end
