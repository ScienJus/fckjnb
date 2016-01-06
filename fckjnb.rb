require 'net/http'
require 'json'
require 'uri'
require 'openssl'

DEBUG = true

class Cookie

  def initialize
    @cookies = {}
  end

  def put set_cookie_array
    return if set_cookie_array.nil?

    set_cookie_array.each do |set_cookie|
      set_cookie.split('; ').each do |cookie|
        k, v = cookie.split('=')
        @cookies[k] = v unless v.nil?
      end
    end
  end

  def [] key
    @cookies[key] || ''
  end

  def to_s
    @cookies.map{ |k, v| "#{k}=#{v}" }.join('; ')
  end

end

class HttpClient

  @@user_agent = 'Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/45.0.2454.101 Safari/537.36'

  @@referer = 'https://jnb.icbc.com.cn/outer/order?area=%E5%8C%97%E4%BA%AC%E5%88%86%E8%A1%8C'

  @@post_content_type = 'application/x-www-form-urlencoded; charset=UTF-8'

  def self.origin(uri)
    "#{uri.scheme}://#{uri.host}"
  end

  def initialize
    @cookie = Cookie.new
  end

  def get(uri)
    puts "get #{uri.to_s}" if DEBUG

    Net::HTTP.start(uri.host, uri.port,
      use_ssl: uri.scheme == 'https',
      verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
      req = Net::HTTP::Get.new(uri)
      req.initialize_http_header(
        'User-Agent' => @@user_agent,
        'Cookie' => @cookie.to_s,
        'Referer' => @@referer
      )
      res = http.request(req)
      @cookie.put(res.get_fields('set-cookie'))
      puts "code: #{res.code}, body: #{res.body}" if DEBUG
      res.body
    end
  end

  def post(uri, form_data = {})
    puts "post uri: #{uri.to_s} data: #{form_data.to_s}" if DEBUG
    Net::HTTP.start(uri.host, uri.port,
      use_ssl: uri.scheme == 'https',
      verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
      req = Net::HTTP::Post.new(uri)
      req.set_form_data(form_data)
      req.initialize_http_header(
        'User-Agent' => @@user_agent,
        'Cookie' => @cookie.to_s,
        'Referer' => @@referer,
        'Content-Type' => @@post_content_type,
        'Origin' => self.class.origin(uri)
      )
      res = http.request(req)
      @cookie.put(res.get_fields('set-cookie'))
      puts "response code: #{res.code}, body: #{res.body}" if DEBUG
      res.body
    end
  end

  def get_cookie(key)
    @cookie[key]
  end
end

client = HttpClient.new

area_name = '北京分行'

session_uri = URI('https://jnb.icbc.com.cn/outer/order')
session_uri.query = URI.encode_www_form(area: area_name)
client.get(session_uri)

sec_bank_uri = URI('https://jnb.icbc.com.cn/app/coin/materials/serlvets/getAeroSecBankServlet')
sec_bank_list = client.post(sec_bank_uri, staBankname: area_name)

in_stock_bank_list = []

JSON.parse(sec_bank_list).each do |sec_bank|
  bank_info_uri = URI('https://jnb.icbc.com.cn/app/coin/materials/serlvets/getAeroBrInfoServlet')
  bank_info_list = client.post(bank_info_uri, staBankname: area_name, secBankname: sec_bank['supbrno2'], brName: '')
  in_stock_bank_list += JSON.parse(bank_info_list).select { |bank_info| bank_info['curtype'] == 4 && bank_info['booknum'] >= 5 }
end

puts in_stock_bank_list
