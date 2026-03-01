require 'nokogiri'

module DevonaBot
  SPECIAL_EVENTS_URL = "#{WIKI_BASE_URL}/wiki/Special_event"

  class SpecialEventsFeed
    def initialize(discord_bot, redis_client, wiki_client)
      @discord_bot = discord_bot
      @redis_client = redis_client
      @wiki_client = wiki_client
      @processing = false
      @disable_messages = ENV['DISABLE_MESSAGES'] == 'true'
    end

    def fetch_events
      html = @wiki_client.fetch_page(SPECIAL_EVENTS_URL)
      return nil unless html

      doc = Nokogiri::HTML(html)
      content = doc.at_css('.mw-parser-output')
      return nil unless content

      heading = content.at_xpath('.//span[@id="Recurring_events"]')
      return nil unless heading

      table = heading.ancestors('h2').first&.next_element
      # Walk forward to find the table if the immediate sibling isn't one
      while table && table.name != 'table'
        table = table.next_element
      end
      return nil unless table

      events = []
      table.css('tbody tr').each do |row|
        cells = row.css('td')
        next if cells.empty? || cells.length < 7

        name = cells[0].at_css('a')&.text&.strip || cells[0].text.strip
        date_text = cells[2].text.strip
        size = cells[3].text.strip
        notes = cells[6].text.strip

        # Parse date like "January 31, 20:00" — grab just the first line before any parenthetical
        date_match = date_text.match(/^(\w+ \d+),\s*(\d+:\d+)/)
        next unless date_match

        month_day = date_match[1]
        time_str = date_match[2]

        events << {
          name: name,
          month_day: month_day,
          time: time_str,
          size: size,
          notes: notes
        }
      end

      events.empty? ? nil : events
    rescue => e
      puts "Error fetching special events: #{e.message}"
      nil
    end

    def next_events(count = 3)
      events = fetch_events
      return nil unless events

      now = Time.now.utc

      dated_events = events.filter_map do |event|
        begin
          parsed = Time.parse("#{event[:month_day]} #{event[:time]} UTC")
          # Build datetime for this year
          event_time = Time.utc(now.year, parsed.month, parsed.day, parsed.hour, parsed.min)
          # If already passed, use next year
          event_time = Time.utc(now.year + 1, parsed.month, parsed.day, parsed.hour, parsed.min) if event_time < now

          event.merge(datetime: event_time)
        rescue => e
          puts "Error parsing event date for #{event[:name]}: #{e.message}"
          nil
        end
      end

      dated_events.sort_by { |e| e[:datetime] }.first(count)
    end

    def build_embed(upcoming)
      return nil if upcoming.nil? || upcoming.empty?

      fields = []

      next_event = upcoming.first
      unix = next_event[:datetime].to_i
      next_value = "**#{next_event[:name]}** (#{next_event[:size]})\n"
      next_value += "<t:#{unix}:F> (<t:#{unix}:R>)"
      next_value += "\n#{next_event[:notes]}" unless next_event[:notes].empty?
      next_value = next_value[0, 1020] + "..." if next_value.length > 1024
      fields << { name: "Next Event", value: next_value, inline: false }

      if upcoming.length > 1
        coming_up = upcoming[1..].map do |event|
          unix = event[:datetime].to_i
          "**#{event[:name]}** (#{event[:size]}) — <t:#{unix}:D> (<t:#{unix}:R>)"
        end.join("\n")
        coming_up = coming_up[0, 1020] + "..." if coming_up.length > 1024
        fields << { name: "Coming Up", value: coming_up, inline: false }
      end

      Discordrb::Webhooks::Embed.new(
        title: "Upcoming Guild Wars Special Events",
        color: 0x8B0000,
        fields: fields,
        footer: Discordrb::Webhooks::EmbedFooter.new(text: "Guild Wars Wiki \u2022 Updates daily at 4:00 AM UTC"),
        timestamp: Time.now.utc
      )
    end

    def get_current_embed
      @wiki_client.login
      upcoming = next_events
      build_embed(upcoming)
    end

    def subscribe(server_id, channel_id)
      key = "#{server_id}:#{channel_id}"
      @redis_client.call("SADD", "special_events:subscriptions", key)

      upcoming = next_events
      embed = build_embed(upcoming)

      if embed && !@disable_messages
        message = @discord_bot.send_message(channel_id, "", false, embed)
        @redis_client.call("SET", "special_events:message:#{channel_id}", message.id.to_s) if message
      end
    end

    def unsubscribe(server_id, channel_id)
      key = "#{server_id}:#{channel_id}"
      @redis_client.call("SREM", "special_events:subscriptions", key)

      message_id = @redis_client.call("GET", "special_events:message:#{channel_id}")
      if message_id && !@disable_messages
        begin
          channel = @discord_bot.channel(channel_id)
          channel.delete_message(message_id.to_i) if channel
        rescue => e
          puts "Could not delete special events message: #{e.message}"
        end
      end
      @redis_client.call("DEL", "special_events:message:#{channel_id}")
    end

    def subscribed?(server_id, channel_id)
      key = "#{server_id}:#{channel_id}"
      @redis_client.call("SISMEMBER", "special_events:subscriptions", key) == 1
    end

    def force_update
      @wiki_client.login

      upcoming = next_events
      embed = build_embed(upcoming)
      return false unless embed

      subscriptions = @redis_client.call("SMEMBERS", "special_events:subscriptions")
      return false if subscriptions.nil? || subscriptions.empty?

      subscriptions.each do |sub|
        _server_id, channel_id = sub.split(':', 2)
        next unless channel_id

        begin
          message_id = @redis_client.call("GET", "special_events:message:#{channel_id}")

          if message_id && !@disable_messages
            begin
              puts "Editing special events message #{message_id} in channel #{channel_id}"
              channel_obj = @discord_bot.channel(channel_id)
              msg = channel_obj.message(message_id.to_i)
              msg.edit("", embed)
              next
            rescue Discordrb::Errors::UnknownMessage
              puts "Previous special events message not found in #{channel_id}, posting new one"
            rescue => e
              puts "Failed to edit special events message in #{channel_id}: #{e.class}: #{e.message}, posting new one"
            end
          end

          unless @disable_messages
            message = @discord_bot.send_message(channel_id, "", false, embed)
            @redis_client.call("SET", "special_events:message:#{channel_id}", message.id.to_s) if message
          end
        rescue => e
          puts "Error updating special events for channel #{channel_id}: #{e.class}: #{e.message}"
        end
      end

      true
    rescue => e
      puts "Error in special events force_update: #{e.class}: #{e.message}"
      false
    end

    def process
      return if @processing

      today = Time.now.utc.strftime('%Y-%m-%d')
      last_update = @redis_client.call("GET", "special_events:last_update")

      if last_update == today
        return if Time.now.utc.hour < 4
        return
      end

      return if Time.now.utc.hour < 4 && last_update == (Date.today - 1).strftime('%Y-%m-%d')

      @processing = true

      @wiki_client.login

      puts "Fetching special events..."
      upcoming = next_events

      if upcoming.nil? || upcoming.empty?
        puts "Failed to fetch any special events data"
        @processing = false
        return
      end

      embed = build_embed(upcoming)
      unless embed
        puts "Failed to build special events embed"
        @processing = false
        return
      end

      subscriptions = @redis_client.call("SMEMBERS", "special_events:subscriptions")
      if subscriptions.nil? || subscriptions.empty?
        puts "No special events subscriptions"
        @redis_client.call("SET", "special_events:last_update", today)
        @processing = false
        return
      end

      subscriptions.each do |sub|
        _server_id, channel_id = sub.split(':', 2)
        next unless channel_id

        begin
          message_id = @redis_client.call("GET", "special_events:message:#{channel_id}")

          if message_id && !@disable_messages
            begin
              channel_obj = @discord_bot.channel(channel_id)
              msg = channel_obj.message(message_id.to_i)
              msg.edit("", embed)
              next
            rescue Discordrb::Errors::UnknownMessage
              puts "Previous special events message not found in #{channel_id}, posting new one"
            rescue => e
              puts "Failed to edit special events message in #{channel_id}: #{e.class}: #{e.message}, posting new one"
            end
          end

          unless @disable_messages
            message = @discord_bot.send_message(channel_id, "", false, embed)
            @redis_client.call("SET", "special_events:message:#{channel_id}", message.id.to_s) if message
          end
        rescue => e
          puts "Error updating special events for channel #{channel_id}: #{e.class}: #{e.message}"
        end

        sleep 1
      end

      @redis_client.call("SET", "special_events:last_update", today)
      puts "Special events updated for #{subscriptions.length} channel(s)"
      @processing = false
    rescue => e
      puts "Error in special events process: #{e.class}: #{e.message}"
      @processing = false
    end
  end
end
