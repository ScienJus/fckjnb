require 'net/http'
require 'json'
require 'uri'
require 'openssl'

module FckJNB

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

  class Http

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
      puts "get #{uri.to_s}" if FckJNB::DEBUG

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
        puts "response code: #{res.code}, body: #{res.body}, cookie: #{@cookie.to_s}" if FckJNB::DEBUG
        res.body
      end
    end

    def post(uri, form_data = {})
      puts "post uri: #{uri.to_s} data: #{form_data.to_s}" if FckJNB::DEBUG
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
        puts "response code: #{res.code}, body: #{res.body}, cookie: #{@cookie.to_s}" if FckJNB::DEBUG
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

  class Client

    def initialize(user_info, area_name = '北京分行', reserved_number = 5)
      @user_info = user_info
      @area_name = area_name
      @reserved_number = reserved_number
    end

    def get_in_stock_bank_list

      client = FckJNB::Http.new

      session_uri = URI('https://jnb.icbc.com.cn/outer/order')
      session_uri.query = URI.encode_www_form(area: @area_name)
      client.get(session_uri)

      sec_bank_uri = URI('https://jnb.icbc.com.cn/app/coin/materials/serlvets/getAeroSecBankServlet')
      sec_bank_list = client.post(sec_bank_uri, staBankname: @area_name)
      sec_bank_list = JSON.parse(sec_bank_list).select { |sec_bank| sec_bank['curtype'].to_i == 5 && sec_bank['booknum'].to_i >= @reserved_number }

      in_stock_bank_list = []

      sec_bank_list.each do |sec_bank|
        bank_info_uri = URI('https://jnb.icbc.com.cn/app/coin/materials/serlvets/getAeroBrInfoServlet')
        bank_info_list = client.post(bank_info_uri, staBankname: @area_name, secBankname: sec_bank['supbrno2'], brName: '')
        in_stock_bank_list += JSON.parse(bank_info_list).select { |bank_info| bank_info['curtype'].to_i == 5 && bank_info['booknum'].to_i >= @reserved_number }
      end

      in_stock_bank_list.map { |bank_info| FckJNB::BankInfo.new(bank_info['brname'], bank_info['braddr'], bank_info['brzo'], bank_info['booknum'].to_i) }
    end


    def get_verify_code_image
      client = FckJNB::Http.new

      session_uri = URI('https://jnb.icbc.com.cn/outer/order')
      session_uri.query = URI.encode_www_form(area: @area_name)
      client.get(session_uri)

      verify_code_image_uri = URI('https://jnb.icbc.com.cn/coin/servlet/ICBCVerifyImage')
      verify_code_image_uri.query = URI.encode_www_form(i: Time.now.to_i)
      image = client.get(verify_code_image_uri)
      @session = client.get_cookie('JSESSIONID');
      image
    end

    def get_sms_verify_code(verify_code)
      client = FckJNB::Http.new
      client.add_cookie('JSESSIONID', @session)
      sms_verify_code_uri = URI('https://jnb.icbc.com.cn/app/coin/materials/serlvets/sendMobileCode')
      result = client.post(sms_verify_code_uri, mobile: @user_info.phone, verify: verify_code, temtype: 1)
      result = JSON.parse(result)[0]
      if result['errtype'] == '0'
        result['codeNumber']
      end
    end

    def fck_the_jnb(bank_info, verify_code, sms_verify_code)
      client = FckJNB::Http.new
      client.add_cookie('JSESSIONID', @session)
      fck_jnb_uri = URI('https://jnb.icbc.com.cn/app/coin/materials/serlvets/bookAeroAppServlet')
      post_data = JSON.generate(
        starBankName: '',
    # Error 500: org.springframework.web.util.NestedServletException:
    # Request processing failed&#59; nested exception is org.json.JSONException:
    # JSONObject[&quot;paperType&quot;] not a string.
        paperType: '0',
        paperNum: @user_info.id,
        name: @user_info.name,
        phone: @user_info.phone,
        verify: verify_code,
        mobileverify: sms_verify_code,
        zoneno: '',
        BRZO: bank_info.brzo,
        orderno: '',
        siteaddr: '',
        curtypenums: "第二批贺岁币@5-#{@reserved_number}",
        bradrr: '',
        querytype: 0,
        curtypenumdel: ''
      )
      client.post(fck_jnb_uri, msg: post_data)
    end
  end

  class UserInfo < Struct.new(:name, :id, :phone); end

  class BankInfo < Struct.new(:name, :address, :brzo, :stock); end

end

class String
  def blank?
    self !~ /[^[:space:]]/
  end
end

user_info = FckJNB::UserInfo.new

puts '请输入姓名：'
user_info.name = gets.chomp

puts '请输入身份证号：'
user_info.id = gets.chomp

puts '请输入手机号：'
user_info.phone = gets.chomp

puts '请输入地区（"北京分行","安徽分行","广西分行","湖北分行","江苏分行），默认为"北京分行"：'

area_name = gets.chomp
area_name = '北京分行' if area_name.blank?

puts '请输入预约数，默认为10：'

reserved_number = gets.chomp
reserved_number = reserved_number.blank? ? 10 : reserved_number.to_i

client = FckJNB::Client.new(user_info, area_name, reserved_number)

puts '正在查询还有库存的银行'

bank_list = client.get_in_stock_bank_list

if bank_list.empty?
  puts '很遗憾，没有查询到有足够库存的银行'
  exit
end

bank_list.each_with_index do |bank, index|
  puts "编号：#{index} 名称：#{bank.name} 地址：#{bank.address}, 库存：#{bank.stock}"
end

puts '请输入你想预约银行的编号：'

index = gets.chomp.to_i

image = client.get_verify_code_image

File.open('verify_code.jpg', 'wb') { |file| file.write(image) }

puts "验证码图片已保存在 #{File.absolute_path('verify_code.jpg')}，请输入验证码："

verify_code = gets.chomp

code = client.get_sms_verify_code(verify_code)

if code
  puts "手机验证码已经发送，编号是#{code}，请输入验证码："

  sms_verify_code = gets.chomp
  puts client.fck_the_jnb(bank_list[index], verify_code, sms_verify_code)
else
  puts '验证码错误'
end
