# frozen_string_literal: true
require_relative '../lib/discord_command'

class DevonaAdminCommand < DevonaBot::Commands::DiscordCommand
  class SubscribeSubcommand < DevonaBot::Commands::DiscordCommand
    def initialize(feed)
      super("subscribe", "subscribe", "Subscribe a channel to daily activity updates")
      @feed = feed
    end

    def register(sub)
      sub.channel('channel', 'The channel to subscribe', required: true)
    end

    def execute(event)
      admin_ids = ENV.fetch('DISCORD_ADMIN_IDS', '').split(',')
      unless admin_ids.include?(event.user.id.to_s)
        event.respond(content: "You don't have permission to run this command.", ephemeral: true)
        return
      end

      server_id = event.server_id.to_s
      channel = event.options['channel']
      channel_id = channel.to_s

      if @feed.subscribed?(server_id, channel_id)
        event.respond(content: "<##{channel_id}> is already subscribed to daily activity updates.", ephemeral: true)
        return
      end

      event.respond(content: "Subscribing <##{channel_id}> to daily Guild Wars activity updates...", ephemeral: true)
      @feed.subscribe(server_id, channel_id)
    end
  end

  class UnsubscribeSubcommand < DevonaBot::Commands::DiscordCommand
    def initialize(feed)
      super("unsubscribe", "unsubscribe", "Unsubscribe a channel from daily activity updates")
      @feed = feed
    end

    def register(sub)
      sub.channel('channel', 'The channel to unsubscribe', required: true)
    end

    def execute(event)
      admin_ids = ENV.fetch('DISCORD_ADMIN_IDS', '').split(',')
      unless admin_ids.include?(event.user.id.to_s)
        event.respond(content: "You don't have permission to run this command.", ephemeral: true)
        return
      end

      server_id = event.server_id.to_s
      channel = event.options['channel']
      channel_id = channel.to_s

      unless @feed.subscribed?(server_id, channel_id)
        event.respond(content: "<##{channel_id}> is not subscribed to daily activity updates.", ephemeral: true)
        return
      end

      @feed.unsubscribe(server_id, channel_id)
      event.respond(content: "<##{channel_id}> has been unsubscribed from daily activity updates.", ephemeral: true)
    end
  end

  class SubscribeEventsSubcommand < DevonaBot::Commands::DiscordCommand
    def initialize(feed)
      super("subscribe_events", "subscribe_events", "Subscribe a channel to special event updates")
      @feed = feed
    end

    def register(sub)
      sub.channel('channel', 'The channel to subscribe', required: true)
    end

    def execute(event)
      admin_ids = ENV.fetch('DISCORD_ADMIN_IDS', '').split(',')
      unless admin_ids.include?(event.user.id.to_s)
        event.respond(content: "You don't have permission to run this command.", ephemeral: true)
        return
      end

      server_id = event.server_id.to_s
      channel = event.options['channel']
      channel_id = channel.to_s

      if @feed.subscribed?(server_id, channel_id)
        event.respond(content: "<##{channel_id}> is already subscribed to special event updates.", ephemeral: true)
        return
      end

      event.respond(content: "Subscribing <##{channel_id}> to Guild Wars special event updates...", ephemeral: true)
      @feed.subscribe(server_id, channel_id)
    end
  end

  class UnsubscribeEventsSubcommand < DevonaBot::Commands::DiscordCommand
    def initialize(feed)
      super("unsubscribe_events", "unsubscribe_events", "Unsubscribe a channel from special event updates")
      @feed = feed
    end

    def register(sub)
      sub.channel('channel', 'The channel to unsubscribe', required: true)
    end

    def execute(event)
      admin_ids = ENV.fetch('DISCORD_ADMIN_IDS', '').split(',')
      unless admin_ids.include?(event.user.id.to_s)
        event.respond(content: "You don't have permission to run this command.", ephemeral: true)
        return
      end

      server_id = event.server_id.to_s
      channel = event.options['channel']
      channel_id = channel.to_s

      unless @feed.subscribed?(server_id, channel_id)
        event.respond(content: "<##{channel_id}> is not subscribed to special event updates.", ephemeral: true)
        return
      end

      @feed.unsubscribe(server_id, channel_id)
      event.respond(content: "<##{channel_id}> has been unsubscribed from special event updates.", ephemeral: true)
    end
  end

  class UpdateSubcommand < DevonaBot::Commands::DiscordCommand
    def initialize(feed)
      super("update", "update", "Force update daily activities for a specific date")
      @feed = feed
    end

    def register(sub)
      sub.string('date', 'Date to fetch (YYYY-MM-DD), defaults to today', required: false)
    end

    def execute(event)
      admin_ids = ENV.fetch('DISCORD_ADMIN_IDS', '').split(',')
      unless admin_ids.include?(event.user.id.to_s)
        event.respond(content: "You don't have permission to run this command.", ephemeral: true)
        return
      end

      date = event.options['date']

      if date
        begin
          Date.parse(date)
        rescue ArgumentError
          event.respond(content: "Invalid date format. Use YYYY-MM-DD.", ephemeral: true)
          return
        end
      end

      event.respond(content: "Updating daily activities#{date ? " for #{date}" : ""}...", ephemeral: true)

      success = @feed.force_update(date)
      if success
        puts "Force updated daily activities#{date ? " for #{date}" : ""}"
      else
        puts "Failed to force update daily activities#{date ? " for #{date}" : ""}"
      end
    end
  end

  def initialize(daily_activities_feed, special_events_feed)
    super(
      "devonaadmin",
      "devonaadmin",
      "DevonaBot admin commands",
      [
        SubscribeSubcommand.new(daily_activities_feed),
        UnsubscribeSubcommand.new(daily_activities_feed),
        UpdateSubcommand.new(daily_activities_feed),
        SubscribeEventsSubcommand.new(special_events_feed),
        UnsubscribeEventsSubcommand.new(special_events_feed)
      ]
    )
  end

  def register(cmd)
  end

  def execute(event)
    event.respond(content: "Use /devonaadmin subscribe <channel> or /devonaadmin unsubscribe <channel>", ephemeral: true)
  end
end
