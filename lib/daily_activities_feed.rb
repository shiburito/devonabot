require 'nokogiri'

module DevonaBot
  WEEKLY_BONUSES_URL = "#{WIKI_BASE_URL}/wiki/Weekly_bonuses"
  ZAISHEN_QUEST_URL = "#{WIKI_BASE_URL}/wiki/Zaishen_Challenge_Quest"
  NICHOLAS_CYCLE_URL = "#{WIKI_BASE_URL}/wiki/Nicholas_the_Traveler/Cycle"
  DAILY_ACTIVITIES_URL = "#{WIKI_BASE_URL}/wiki/Daily_activities"

  class DailyActivitiesFeed
    def initialize(discord_bot, redis_client, wiki_client)
      @discord_bot = discord_bot
      @redis_client = redis_client
      @wiki_client = wiki_client
      @processing = false
      @disable_messages = ENV['DISABLE_MESSAGES'] == 'true'
    end

    def fetch_weekly_bonuses
      html = @wiki_client.fetch_page(WEEKLY_BONUSES_URL)
      return nil unless html

      doc = Nokogiri::HTML(html)
      content = doc.at_css('.mw-parser-output')
      return nil unless content

      bonuses = []
      this_week_heading = content.at_xpath('.//h2[.//span[@id="This_week"]]')
      return nil unless this_week_heading

      node = this_week_heading.next_sibling
      current_bonus = nil

      while node
        break if node.name == 'h2'

        if node.name == 'ul'
          node.css('li').each do |li|
            name = li.at_css('b')&.text&.strip
            date = li.at_css('i')&.text&.strip
            current_bonus = { name: name, date: date, description: nil } if name
          end
        elsif node.name == 'dl' && current_bonus
          dd = node.at_css('dd')
          if dd
            current_bonus[:description] = dd.text.strip
            bonuses << current_bonus
            current_bonus = nil
          end
        end

        node = node.next_sibling
      end

      bonuses << current_bonus if current_bonus
      bonuses.empty? ? nil : bonuses
    rescue => e
      puts "Error fetching weekly bonuses: #{e.message}"
      nil
    end

    def fetch_zaishen_quests(date = nil)
      html = @wiki_client.fetch_page(ZAISHEN_QUEST_URL)
      return nil unless html

      doc = Nokogiri::HTML(html)
      content = doc.at_css('.mw-parser-output')
      return nil unless content

      table = content.at_css('table')
      return nil unless table

      today_row = if date
        date_str = Date.parse(date).strftime('%-d %B %Y')
        table.xpath('.//tr').find { |row| row.at_css('td')&.text&.strip == date_str }
      else
        table.at_xpath('.//tr[contains(@style, "font-weight: bold")]')
      end
      return nil unless today_row

      cells = today_row.css('td')
      return nil if cells.length < 6

      date = cells[0].text.strip
      mission = cells[1].at_css('a')&.text&.strip || cells[1].text.strip
      bounty = cells[2].at_css('a')&.text&.strip || cells[2].text.strip
      combat = cells[3].at_css('a')&.text&.strip || cells[3].text.strip
      vanquish = cells[4].at_css('a')&.text&.strip || cells[4].text.strip

      coins_text = cells[5].text.strip
      total_match = coins_text.match(/=\s*(\d+)/)
      total_coins = total_match ? total_match[1].to_i : nil

      {
        date: date,
        mission: mission,
        bounty: bounty,
        combat: combat,
        vanquish: vanquish,
        total_coins: total_coins
      }
    rescue => e
      puts "Error fetching Zaishen quests: #{e.message}"
      nil
    end

    def fetch_nicholas_gifts(date = nil)
      html = @wiki_client.fetch_page(NICHOLAS_CYCLE_URL)
      return nil unless html

      doc = Nokogiri::HTML(html)
      content = doc.at_css('.mw-parser-output')
      return nil unless content

      table = content.at_css('table')
      return nil unless table

      row = if date
        target = Date.parse(date)
        # Nicholas changes weekly on Mondays — find the week containing the target date
        best_row = nil
        table.xpath('.//tr[td]').each do |tr|
          week_text = tr.at_css('td')&.text&.strip
          next unless week_text
          begin
            week_date = Date.parse(week_text)
            best_row = tr if week_date <= target
          rescue ArgumentError
            next
          end
        end
        best_row
      else
        table.at_xpath('.//tr[contains(@style, "font-weight: bold")]')
      end
      return nil unless row

      cells = row.css('td')
      return nil if cells.length < 5

      week = cells[0].text.strip
      item = cells[1].text.strip
      location = cells[2].at_css('a')&.text&.strip || cells[2].text.strip
      region = cells[3].at_css('a')&.text&.strip || cells[3].text.strip
      campaign = cells[4].at_css('a')&.text&.strip || cells[4].text.strip

      {
        week: week,
        item: item,
        location: location,
        region: region,
        campaign: campaign
      }
    rescue => e
      puts "Error fetching Nicholas gifts: #{e.message}"
      nil
    end

    def fetch_daily_extras(date = nil)
      html = @wiki_client.fetch_page(DAILY_ACTIVITIES_URL)
      return nil unless html

      doc = Nokogiri::HTML(html)
      content = doc.at_css('.mw-parser-output')
      return nil unless content

      table = content.at_css('table')
      return nil unless table

      row = if date
        date_str = Date.parse(date).strftime('%-d %B %Y')
        table.xpath('.//tr').find { |r| r.at_css('td')&.text&.strip == date_str }
      else
        table.at_xpath('.//tr[contains(@style, "font-weight: bold")]')
      end
      return nil unless row

      cells = row.css('td')
      return nil if cells.length < 8

      # Columns: Date, Mission, Bounty, Combat, Vanquish, Shining Blade, Vanguard Quest, Nicholas Sandford
      vanguard = cells[6].at_css('a')&.text&.strip || cells[6].text.strip
      sandford = cells[7].at_css('a')&.text&.strip || cells[7].text.strip

      # Get the full quest name from the link title for vanguard
      vanguard_title = cells[6].at_css('a')&.attr('title')&.strip

      {
        vanguard: vanguard,
        vanguard_title: vanguard_title,
        sandford: sandford
      }
    rescue => e
      puts "Error fetching daily extras: #{e.message}"
      nil
    end

    def build_embed(bonuses, quests, nicholas = nil, extras = nil)
      fields = []

      if bonuses && !bonuses.empty?
        bonus_text = bonuses.map do |b|
          line = "**#{b[:name]}**"
          line += "\n#{b[:description]}" if b[:description]
          line
        end.join("\n\n")
        bonus_text = bonus_text[0, 1020] + "..." if bonus_text.length > 1024
        fields << { name: "Weekly Bonuses", value: bonus_text, inline: false }
      end

      if quests
        fields << { name: "Zaishen Mission", value: quests[:mission], inline: true }
        fields << { name: "Zaishen Bounty", value: quests[:bounty], inline: true }
        fields << { name: "Zaishen Combat", value: quests[:combat], inline: true }
        fields << { name: "Zaishen Vanquish", value: quests[:vanquish], inline: true }
        if quests[:total_coins]
          fields << { name: "Total Zaishen Coins", value: "#{quests[:total_coins]} Copper Zaishen Coins", inline: true }
        end
      end

      if extras
        fields << { name: "Vanguard Quest", value: extras[:vanguard_title] || extras[:vanguard], inline: true }
        fields << { name: "Nicholas Sandford", value: "5 #{extras[:sandford]} x 5", inline: true }
      end

      if nicholas
        nick_text = "**#{nicholas[:item]}** x 5\n#{nicholas[:location]} (#{nicholas[:region]}, #{nicholas[:campaign]})"
        fields << { name: "Nicholas the Traveler", value: nick_text, inline: false }
      end

      return nil if fields.empty?

      Discordrb::Webhooks::Embed.new(
        title: "Daily Guild Wars Activities",
        color: 0x8B0000,
        fields: fields,
        footer: Discordrb::Webhooks::EmbedFooter.new(text: "Guild Wars Wiki \u2022 Updates daily at 4:00 AM UTC"),
        timestamp: Time.now.utc
      )
    end

    def get_today_embed
      @wiki_client.login
      bonuses = fetch_weekly_bonuses
      quests = fetch_zaishen_quests
      nicholas = fetch_nicholas_gifts
      extras = fetch_daily_extras
      build_embed(bonuses, quests, nicholas, extras)
    end

    def subscribe(server_id, channel_id)
      key = "#{server_id}:#{channel_id}"
      @redis_client.call("SADD", "daily_activities:subscriptions", key)

      bonuses = fetch_weekly_bonuses
      quests = fetch_zaishen_quests
      nicholas = fetch_nicholas_gifts
      extras = fetch_daily_extras
      embed = build_embed(bonuses, quests, nicholas, extras)

      if embed && !@disable_messages
        message = @discord_bot.send_message(channel_id, "", false, embed)
        @redis_client.call("SET", "daily_activities:message:#{channel_id}", message.id.to_s) if message
      end
    end

    def unsubscribe(server_id, channel_id)
      key = "#{server_id}:#{channel_id}"
      @redis_client.call("SREM", "daily_activities:subscriptions", key)

      message_id = @redis_client.call("GET", "daily_activities:message:#{channel_id}")
      if message_id && !@disable_messages
        begin
          channel = @discord_bot.channel(channel_id)
          channel.delete_message(message_id.to_i) if channel
        rescue => e
          puts "Could not delete daily activities message: #{e.message}"
        end
      end
      @redis_client.call("DEL", "daily_activities:message:#{channel_id}")
    end

    def subscribed?(server_id, channel_id)
      key = "#{server_id}:#{channel_id}"
      @redis_client.call("SISMEMBER", "daily_activities:subscriptions", key) == 1
    end

    def force_update(date = nil)
      @wiki_client.login

      bonuses = fetch_weekly_bonuses
      quests = fetch_zaishen_quests(date)
      nicholas = fetch_nicholas_gifts(date)
      extras = fetch_daily_extras(date)
      embed = build_embed(bonuses, quests, nicholas, extras)
      return false unless embed

      subscriptions = @redis_client.call("SMEMBERS", "daily_activities:subscriptions")
      return false if subscriptions.nil? || subscriptions.empty?

      subscriptions.each do |sub|
        _server_id, channel_id = sub.split(':', 2)
        next unless channel_id

        begin
          message_id = @redis_client.call("GET", "daily_activities:message:#{channel_id}")

          if message_id && !@disable_messages
            begin
              puts "Editing daily activities message #{message_id} in channel #{channel_id}"
              channel_obj = @discord_bot.channel(channel_id)
              msg = channel_obj.message(message_id.to_i)
              msg.edit("", embed)
              next
            rescue Discordrb::Errors::UnknownMessage
              puts "Previous daily activities message not found in #{channel_id}, posting new one"
            rescue => e
              puts "Failed to edit daily activities message in #{channel_id}: #{e.class}: #{e.message}, posting new one"
            end
          end

          unless @disable_messages
            message = @discord_bot.send_message(channel_id, "", false, embed)
            @redis_client.call("SET", "daily_activities:message:#{channel_id}", message.id.to_s) if message
          end
        rescue => e
          puts "Error updating daily activities for channel #{channel_id}: #{e.class}: #{e.message}"
        end
      end

      true
    rescue => e
      puts "Error in force_update: #{e.class}: #{e.message}"
      false
    end

    def process
      return if @processing

      today = Time.now.utc.strftime('%Y-%m-%d')
      last_update = @redis_client.call("GET", "daily_activities:last_update")

      if last_update == today
        return if Time.now.utc.hour < 4
        return
      end

      return if Time.now.utc.hour < 4 && last_update == (Date.today - 1).strftime('%Y-%m-%d')

      @processing = true

      @wiki_client.login

      puts "Fetching daily activities..."
      bonuses = fetch_weekly_bonuses
      quests = fetch_zaishen_quests
      nicholas = fetch_nicholas_gifts
      extras = fetch_daily_extras

      if bonuses.nil? && quests.nil? && nicholas.nil? && extras.nil?
        puts "Failed to fetch any daily activities data"
        @processing = false
        return
      end

      embed = build_embed(bonuses, quests, nicholas, extras)
      unless embed
        puts "Failed to build daily activities embed"
        @processing = false
        return
      end

      subscriptions = @redis_client.call("SMEMBERS", "daily_activities:subscriptions")
      if subscriptions.nil? || subscriptions.empty?
        puts "No daily activities subscriptions"
        @redis_client.call("SET", "daily_activities:last_update", today)
        @processing = false
        return
      end

      subscriptions.each do |sub|
        _server_id, channel_id = sub.split(':', 2)
        next unless channel_id

        begin
          message_id = @redis_client.call("GET", "daily_activities:message:#{channel_id}")

          if message_id && !@disable_messages
            begin
              channel_obj = @discord_bot.channel(channel_id)
              msg = channel_obj.message(message_id.to_i)
              msg.edit("", embed)
              next
            rescue Discordrb::Errors::UnknownMessage
              puts "Previous daily activities message not found in #{channel_id}, posting new one"
            rescue => e
              puts "Failed to edit daily activities message in #{channel_id}: #{e.class}: #{e.message}, posting new one"
            end
          end

          unless @disable_messages
            message = @discord_bot.send_message(channel_id, "", false, embed)
            @redis_client.call("SET", "daily_activities:message:#{channel_id}", message.id.to_s) if message
          end
        rescue => e
          puts "Error updating daily activities for channel #{channel_id}: #{e.class}: #{e.message}"
        end

        sleep 1
      end

      @redis_client.call("SET", "daily_activities:last_update", today)
      puts "Daily activities updated for #{subscriptions.length} channel(s)"
      @processing = false
    rescue => e
      puts "Error in daily activities process: #{e.class}: #{e.message}"
      @processing = false
    end
  end
end
