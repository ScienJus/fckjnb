require 'net/http'
require 'json'
require 'uri'
require 'openssl'

DEBUG = false

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

  def []=(key, value)
    @cookies[key] = value || ''
  end

  def to_s
    @cookies.map{ |k, v| "#{k}=#{v}" }.join('; ')
  end

end

class HttpClient

  @@user_agent = 'Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/45.0.2454.101 Safari/537.36'

  @@referer = 'https://jnb.icbc.com.cn/outer/order'

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
      puts "response code: #{res.code}, body: #{res.body}, cookie: #{@cookie.to_s}" if DEBUG
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
      puts "response code: #{res.code}, body: #{res.body}, cookie: #{@cookie.to_s}" if DEBUG
      res.body
    end
  end

  def get_cookie(key)
    @cookie[key]
  end

  def add_cookie(key, value)
    @cookie[key] = value
  end
end

AREA_NAME = '北京分行'

MIN_STOCK_NUM = 0;

def get_in_stock_bank_list

  client = HttpClient.new

  session_uri = URI('https://jnb.icbc.com.cn/outer/order')
  session_uri.query = URI.encode_www_form(area: AREA_NAME)
  client.get(session_uri)

  sec_bank_uri = URI('https://jnb.icbc.com.cn/app/coin/materials/serlvets/getAeroSecBankServlet')
  sec_bank_list = client.post(sec_bank_uri, staBankname: AREA_NAME)

  in_stock_bank_list = []

  JSON.parse(sec_bank_list).each do |sec_bank|
    bank_info_uri = URI('https://jnb.icbc.com.cn/app/coin/materials/serlvets/getAeroBrInfoServlet')
    bank_info_list = client.post(bank_info_uri, staBankname: AREA_NAME, secBankname: sec_bank['supbrno2'], brName: '')
    in_stock_bank_list += JSON.parse(bank_info_list).select { |bank_info| bank_info['curtype'].to_i == 5 && bank_info['booknum'].to_i >= MIN_STOCK_NUM }
  end

  in_stock_bank_list
end


def get_verify_code_image
  client = HttpClient.new

  session_uri = URI('https://jnb.icbc.com.cn/outer/order')
  session_uri.query = URI.encode_www_form(area: AREA_NAME)
  client.get(session_uri)

  verify_code_image_uri = URI('https://jnb.icbc.com.cn/coin/servlet/ICBCVerifyImage')
  verify_code_image_uri.query = URI.encode_www_form(i: Time.now.to_i)
  image = client.get(verify_code_image_uri)
  return image, client.get_cookie('JSESSIONID')
end

def fck_the_jnb(user_info, bank_brzo, session, verify_code)
  client = HttpClient.new
  client.add_cookie('JSESSIONID', 'session')
  fck_jnb_uri = URI('https://jnb.icbc.com.cn/app/coin/materials/serlvets/bookAeroAppServlet')
  post_data = JSON.generate(
    starBankName: '',
    paperType: 0,
    paperNum: user_info.id,
    name: user_info.name,
    phone: user_info.phone,
    verify: verify_code,
    mobileverify: '',
    zoneno: '',
    BRZO: bank_brzo,
    orderno: '',
    siteaddr: '',
    curtypenums: '第一批贺岁币@4-5',
    bradrr: '',
    querytype: 0,
    curtypenumdel: ''
  )
  client.post(uri, msg: post_data)
end

class UserInfo < Struct.new(:name, :id, :phone); end

user_info = UserInfo.new

puts '请输入姓名'
user_info.name = gets.chomp

puts '请输入身份证号'
user_info.id = gets.chomp

puts '请输入手机号'
user_info.phone = gets.chomp

get_in_stock_bank_list.each do |bank|
  image, session = get_verify_code_image

  File.open('verify_code.jpg', 'wb') { |file| file.write(image) }

  puts '请输入验证码'

  verify_code = gets.chomp

  fck_the_jnb(user_info, bank['brzo'], session, verify_code)
end
