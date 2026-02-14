require 'net/http'
require 'json'
require 'uri'
require 'nokogiri'
module DevonaBot

  WIKI_BASE_URL = 'https://wiki.guildwars.com'
  WIKI_API_URL = "#{WIKI_BASE_URL}/api.php"
  GAME_UPDATES_URL = "#{WIKI_BASE_URL}/wiki/Game_updates"

  class GameUpdateFeed
    def initialize(discord_bot, redis_client)
      @discord_bot = discord_bot
      @redis_client = redis_client
      @channels = ENV['GAME_UPDATES_DISCORD_CHANNELS'].split(',')
      @processing = false
      @disable_messages = ENV['DISABLE_MESSAGES'] == 'true'
      @cookies = {}
      @logged_in = false
    end

    def wiki_login
      username = ENV['GW_WIKI_USERNAME']
      password = ENV['GW_WIKI_PASSWORD']
      unless username && password
        puts "GW_WIKI_USERNAME or GW_WIKI_PASSWORD not set, fetching without auth"
        return false
      end

      api_uri = URI(WIKI_API_URL)

      # Step 1: Fetch a login token
      token_uri = URI("#{WIKI_API_URL}?action=query&meta=tokens&type=login&format=json")
      token_response = wiki_get(token_uri)
      unless token_response.is_a?(Net::HTTPSuccess)
        puts "Failed to fetch login token: HTTP #{token_response.code}"
        return false
      end
      store_cookies(token_response)

      token_data = JSON.parse(token_response.body)
      login_token = token_data.dig('query', 'tokens', 'logintoken')
      unless login_token
        puts "Could not extract login token from API response: #{token_response.body}"
        return false
      end

      # Step 2: POST login with credentials and token
      login_response = wiki_post(api_uri, {
        'action' => 'login',
        'lgname' => username,
        'lgpassword' => password,
        'lgtoken' => login_token,
        'format' => 'json'
      })
      store_cookies(login_response)

      result = JSON.parse(login_response.body)
      if result.dig('login', 'result') == 'Success'
        puts "Logged into wiki as #{result.dig('login', 'lgusername')}"
        @logged_in = true
      else
        puts "Wiki login failed: #{result.to_json}"
        false
      end
    rescue => e
      puts "Wiki login error: #{e.message}"
      false
    end

    def wiki_get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = 'DevonaBot/1.0'
      request['Cookie'] = cookie_header unless @cookies.empty?
      http.request(request)
    end

    def wiki_post(uri, params)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri)
      request['User-Agent'] = 'DevonaBot/1.0'
      request['Cookie'] = cookie_header unless @cookies.empty?
      request.set_form_data(params)
      http.request(request)
    end

    def store_cookies(response)
      Array(response.get_fields('set-cookie')).each do |cookie|
        name, value = cookie.split(';').first.split('=', 2)
        @cookies[name.strip] = value.strip
      end
    end

    def cookie_header
      @cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
    end

    def fetch_page(url)
      uri = URI(url)
      response = wiki_get(uri)
      if response.is_a?(Net::HTTPSuccess)
        response.body
      else
        nil
      end
    rescue => e
      puts "There was an error fetching the game updates page #{e}"
      nil
    end

    def parse_list(ul_node, depth = 0)
      items = []
      ul_node.xpath('./li').each do |li|
        indent = "  " * depth
        bullet = depth == 0 ? "•" : "◦"

        text_parts = []
        li.children.each do |child|
          if child.text? || child.name == 'a' || child.name == 'b' || child.name == 'i' || child.name == 'span'
            text_parts << child.text
          elsif child.name != 'ul'
            text_parts << child.text
          end
        end
        text = text_parts.join.strip
        items << "#{indent}#{bullet} #{text}" unless text.empty?

        # Handle nested lists
        li.xpath('./ul').each do |nested_ul|
          items.concat(parse_list(nested_ul, depth + 1))
        end
      end
      items
    end

    def parse_update_page(html)
      doc = Nokogiri::HTML(html)
      content = doc.at_css('.mw-parser-output')
      return nil unless content

      sections = []
      current_section = nil
      current_subsection = nil
      current_feature = nil

      content.children.each do |node|
        case node.name
        when 'h2'
          headline = node.at_css('.mw-headline')&.text&.strip
          next unless headline
          current_section = { title: headline, intro: [], subsections: [], items: [] }
          sections << current_section
          current_subsection = nil
          current_feature = nil
        when 'h3'
          next unless current_section
          headline = node.at_css('.mw-headline')&.text&.strip
          next unless headline
          current_subsection = { title: headline, features: [], items: [] }
          current_section[:subsections] << current_subsection
          current_feature = nil
        when 'h4'
          next unless current_subsection
          headline = node.at_css('.mw-headline')&.text&.strip
          next unless headline
          current_feature = { title: headline, items: [] }
          current_subsection[:features] << current_feature
        when 'p'
          text = node.text.strip
          next if text.empty?
          if current_subsection
            current_subsection[:items] << text
          elsif current_section
            current_section[:intro] << text
          end
        when 'ul'
          items = parse_list(node)
          if current_feature
            current_feature[:items].concat(items)
          elsif current_subsection
            current_subsection[:items].concat(items)
          elsif current_section
            current_section[:items].concat(items)
          end
        end
      end

      sections
    end

    def format_update_for_discord(date_id, sections)
      update_section = sections.find { |s| s[:title]&.include?('Update') }
      return nil unless update_section

      title = update_section[:title]
      wiki_url = "#{WIKI_BASE_URL}/wiki/Feedback:Game_updates/#{date_id}"

      embeds = []
      current_embed = {
        title: title,
        url: wiki_url,
        color: 0x8B0000,
        fields: [],
        footer: { text: "Guild Wars Wiki" },
        timestamp: Time.now.utc.iso8601
      }

      unless update_section[:intro].empty?
        intro_text = update_section[:intro].join("\n\n")
        if intro_text.length <= 4096
          current_embed[:description] = intro_text
        end
      end

      update_section[:subsections].each do |subsection|
        content_parts = []

        content_parts.concat(subsection[:items])

        subsection[:features].each do |feature|
          content_parts << "**#{feature[:title]}**"
          content_parts.concat(feature[:items])
        end

        next if content_parts.empty?

        chunks = []
        current_chunk = []
        current_length = 0

        content_parts.each do |item|
          item_length = item.length + 1
          if current_length + item_length > 1000 && !current_chunk.empty?
            chunks << current_chunk.join("\n")
            current_chunk = [item]
            current_length = item_length
          else
            current_chunk << item
            current_length += item_length
          end
        end
        chunks << current_chunk.join("\n") unless current_chunk.empty?

        chunks.each_with_index do |chunk, idx|
          field_name = idx == 0 ? subsection[:title] : "#{subsection[:title]} (cont.)"

          embed_size = current_embed.to_json.length
          if current_embed[:fields].length >= 25 || embed_size + chunk.length > 5500
            embeds << current_embed
            current_embed = {
              title: "#{title} (continued)",
              url: wiki_url,
              color: 0x8B0000,
              fields: [],
              footer: { text: "Guild Wars Wiki" },
              timestamp: Time.now.utc.iso8601
            }
          end

          current_embed[:fields] << {
            name: field_name,
            value: chunk,
            inline: false
          }
        end
      end

      if current_embed[:fields].empty? && !update_section[:items].empty?
        content = update_section[:items].join("\n")
        content = content[0, 1020] + "..." if content.length > 1024
        current_embed[:fields] << {
          name: "Changes",
          value: content,
          inline: false
        }
      end

      embeds << current_embed unless current_embed[:fields].empty?

      return nil if embeds.empty?
      embeds
    end

    def post_to_discord(channel, embeds)
      embeds = [embeds] unless embeds.is_a?(Array)

      embeds.each_with_index do |embed, idx|
        @discord_bot.send_message(channel, "", false, embed) unless @disable_messages
        sleep 1 if idx < embeds.length - 1
      end

      true
    end

    def store_update(channel, date_id, data)
      @redis_client.call("HSET", "gw_update:#{channel}:#{date_id}", *data.flatten) unless @disable_messages
    end

    def update_exists?(channel,date_id)
      @redis_client.call("EXISTS", "gw_update:#{channel}:#{date_id}") == 1
    end

    def process
      return if @processing
      @processing = true

      wiki_login unless @logged_in

      puts "Fetching game updates page..."
      main_page = fetch_page(GAME_UPDATES_URL)
      unless main_page
        puts "Failed to fetch game updates page"
        @processing = false
      end

      updates_to_post = []

      (0..6).each do |days_ago|
        date = (Date.today - days_ago).strftime('%Y%m%d')
        next if updates_to_post.any? { |u| u[:date_id] == date }
        update_url = "#{WIKI_BASE_URL}/wiki/Feedback:Game_updates/#{date}"
        update_page = fetch_page(update_url)
        next unless update_page

        sections = parse_update_page(update_page)
        next unless sections
        embeds = format_update_for_discord(date, sections)
        next unless embeds

        updates_to_post << { date_id: date, embeds: embeds }
      end

      puts "Found #{updates_to_post.length} updates from the last 7 days"

      @channels.each do |channel|
        updates_posted = 0
        updates_to_post.sort_by { |u| u[:date_id] }.each do |update|
          next if update_exists?(channel, update[:date_id])
          puts "Posting update #{update[:date_id]} to Discord (#{update[:embeds].length} embed(s))..."
          success = post_to_discord(channel, update[:embeds])

          if success
            store_update(channel, update[:date_id], {
              'date_id' => update[:date_id],
              'posted_at' => Time.now.utc.to_s
            })
            puts "Successfully posted update #{update[:date_id]}"
            updates_posted += 1
          else
            puts "Failed to post update #{update[:date_id]}"
          end

          sleep 2
        end
        puts "Posted #{updates_posted} new updates to #{channel}" if updates_posted > 0
      end


      @processing = false
    end

  end
end