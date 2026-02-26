require 'net/http'
require 'json'
require 'uri'

module DevonaBot
  WIKI_BASE_URL = 'https://wiki.guildwars.com'
  WIKI_API_URL = "#{WIKI_BASE_URL}/api.php"

  class WikiClient
    attr_reader :logged_in

    def initialize
      @cookies = {}
      @logged_in = false
      @mutex = Mutex.new
    end

    def login
      @mutex.synchronize do
        return true if @logged_in

        username = ENV['GW_WIKI_USERNAME']
        password = ENV['GW_WIKI_PASSWORD']
        unless username && password
          puts "GW_WIKI_USERNAME or GW_WIKI_PASSWORD not set, fetching without auth"
          return false
        end

        api_uri = URI(WIKI_API_URL)

        token_uri = URI("#{WIKI_API_URL}?action=query&meta=tokens&type=login&format=json")
        token_response = get(token_uri)
        unless token_response.is_a?(Net::HTTPSuccess)
          puts "Failed to fetch wiki login token: HTTP #{token_response.code}"
          return false
        end
        store_cookies(token_response)

        token_data = JSON.parse(token_response.body)
        login_token = token_data.dig('query', 'tokens', 'logintoken')
        unless login_token
          puts "Could not extract login token from API response: #{token_response.body}"
          return false
        end

        login_response = post(api_uri, {
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
      end
    rescue => e
      puts "Wiki login error: #{e.message}"
      false
    end

    def get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = 'DevonaBot/1.0'
      request['Cookie'] = cookie_header unless @cookies.empty?
      http.request(request)
    end

    def post(uri, params)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri)
      request['User-Agent'] = 'DevonaBot/1.0'
      request['Cookie'] = cookie_header unless @cookies.empty?
      request.set_form_data(params)
      http.request(request)
    end

    def fetch_page(url)
      uri = URI(url)
      response = get(uri)
      if response.is_a?(Net::HTTPSuccess)
        response.body
      else
        nil
      end
    rescue => e
      puts "Error fetching #{url}: #{e}"
      nil
    end

    private

    def store_cookies(response)
      Array(response.get_fields('set-cookie')).each do |cookie|
        name, value = cookie.split(';').first.split('=', 2)
        @cookies[name.strip] = value.strip
      end
    end

    def cookie_header
      @cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
    end
  end
end
