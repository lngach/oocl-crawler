module Crawler
  class OoclService < BaseService
    SERVICE_NAME = 'OoclService'.freeze
    MAX_RETRY_TIME = 1
    SLEEP_TIME = 10

    MAIN_URL = URI 'https://www.oocl.com/eng/ourservices/eservices/cargotracking/Pages/cargotracking.aspx'
    SECOND_URL = 'http://moc.oocl.com/party/cargotracking/ct_search_from_other_domain.jsf?ANONYMOUS_BEHAVIOR=BUILD_UP&domainName=PARTY_DOMAIN&ENTRY_TYPE=OOCL&ENTRY=MCC&ctSearchType=CNTR&ctShipmentNumber=%{con}'.freeze
    THIRD_URL = 'http://moc.oocl.com/party/cargotracking/ct_search_from_other_domain.jsf?ANONYMOUS_TOKEN=%{con}&ENTRY=MCC&ENTRY_TYPE=OOCL&PREFER_LANGUAGE=en-US'.freeze

    def initialize(cntr_nos)
      @log_service = CrawlerLog.new('oocl_crawl_containers_journey')
      @containers = cntr_nos

      @header = {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.137 Safari/537.36',
        'Connection' => 'keep-alive'
      }
      @default_second_page_params = {
        'hiddenForm:_link_hidden_' => 'hiddenForm:goToCargoTrackingCNTR',
        'hiddenForm:supportUtfChars' => 'true'
      }

      @result = []
      @current_index = -1
    end

    def execute
      @containers.each do |container|
        @current_index += 1
        reset(container)
        @log_service.info "<--- Start crawl container journey: #{@current_cntr_no} --->"
        try = 0

        loop do
          break if (try += 1) > MAX_RETRY_TIME

          @log_service.info "Retry times: #{try}" unless try.zero?

          if try > MAX_RETRY_TIME
            @log_service.error("Error Class: Crawler::Error, Message: #{ERR_REACH_MAX_RETRY}", { container_number: @current_cntr_no })
          end

          next unless multi_session_request
        end
        sleep(SLEEP_TIME)
      end
      @log_service.info '<--- Finished ---> '
      @resultt = { success: true, containers: @result }
    rescue Exception => e
      @log_service.error("Error Class: #{e.class}, Message: #{e.message}", { container_number: @current_cntr_no })
      @log_service.info("Finish with ERROR: #{e.class}, #{e.message}. Nothing crawled!")
      @result = { success: false, message: "Error Class: #{e.class}, Message: #{e.message}" }
    end

    private

    def multi_session_request
      fetch_main_page
      cross_session_request
      true
    end

    def cross_session_request
      cross_domain = URI format(SECOND_URL, con: @current_cntr_no)
      request = Net::HTTP.new(cross_domain.hostname, cross_domain.port)
      request.start do |http|
        fetch_2nd_page(http)
        fetch_3rd_page(http)
      end
    end

    def fetch_main_page
      @log_service.info "\nOpenning Main page.."

      request = Net::HTTP.new(MAIN_URL.hostname, MAIN_URL.port)
      request.use_ssl = true
      request.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request.start do |http|
        req = Net::HTTP::Post.new(MAIN_URL, @header)

        res = http.request(req)
        @cookie = res['Set-cookie']

        @log_service.info "\nSaved cookie from browser"
        @log_service.info "\n======= START COOKIE ======="
        @log_service.info "\n#{@cookie}"
        @log_service.info "\n======= END COOKIE ======="

        @log_service.info "\nParsing params from inputs at Main page.."
        parse_main_page_params(res.body)
      end
    end

    def fetch_2nd_page(http)
      @log_service.info "\nOpenning Second page with parameters crawled from Main page..."

      req = Net::HTTP::Post.new(format(SECOND_URL, con: @current_cntr_no), single_session)
      req.body = URI.encode_www_form(@params)

      res = http.request(req)

      @log_service.info "\nParsing params from inputs at Second page.."
      parse_second_page_params(res.body)
    end

    def fetch_3rd_page(http)
      @log_service.info "\nHit Third step! Openning Third page..."

      req = Net::HTTP::Post.new(format(THIRD_URL, con: @current_cntr_no), single_session)
      req.body = URI.encode_www_form(@params)

      res = http.request(req)
      @log_service.info "\nFinal step! Extracting crawled data..."
      check_valid_reponse!(res)
      extract_info_from_third_page(res.body)
    end

    def parse_main_page_params(html)
      page = Nokogiri::HTML(html)

      inputs = page.search 'input'
      inputs.each do |elm|
        key = elm['name']
        next if key.nil?

        value = elm['value']
        @params[key] = value
      end

      @params.merge!(@default_main_params)
    end

    def parse_second_page_params(html)
      @params = {}
      page = Nokogiri::HTML(html)

      inputs = page.search('input')
      inputs.each do |elm|
        key = elm['name']
        next if key.nil?

        value = elm['value']
        @params[key] = value
        @user_token = value.sub!('USER_TOKEN=', '') if key == 'USER_TOKEN'
      end

      @params.merge!(@default_second_page_params)
    end

    def extract_info_from_third_page(html)
      page = Nokogiri::HTML(html)
      gather_info(page)
      gather_history(page)
    end

    def gather_info(page)
      rows = page.search('#Tab1 #eventListTable tr')
      rows.drop(1).each do |row|
        col = row.search('td')

        td4 = col.css('td:nth-child(4)')
        td5 = col.css('td:nth-child(5)')
        td6 = col.css('td:nth-child(6)')

        dep_info = td4.search('span')
        arr_info = td6.search('span')
        con_info = { "#{@current_cntr_no}": {} }
        con_info[@current_cntr_no.to_s] = {
          pol: dep_info.css('span:nth-child(1)').text,
          atd: dep_info.css('span:nth-child(3)').text,
          pod: arr_info.css('span:nth-child(1)').text,
          ata: arr_info.css('span:nth-child(3)').text,
          vessel_name: td5.text.strip.gsub(/\n+\t+/, '').squeeze(' ')
        }
        @result << con_info
      end
    end

    def gather_history(page)
      rows = page.search('#Tab2 #eventListTable tr')
      histories = {
        histories: []
      }

      rows.drop(1).each do |row|
        col = row.search('td')

        td1 = col.css('td:nth-child(1)')
        td2 = col.css('td:nth-child(2)')
        td3 = col.css('td:nth-child(3)')
        td5 = col.css('td:nth-child(5)')

        histories[:histories] << {
          event: td1.text.strip.gsub(/\n+\t+/, '').squeeze(' '),
          facility: td2.text.strip.gsub(/\n+\t+/, '').squeeze(' '),
          location: td3.text.strip.gsub(/\n+\t+/, '').squeeze(' '),
          time: td5.text.strip.gsub(/\n+\t+/, '').squeeze(' ')
        }
      end
      @result[@current_index][@current_cntr_no.to_s].merge!(histories)
    end

    def single_session
      @header.merge!({ 'Cookie' => @cookie })
    end

    def reset(cntr_no)
      @current_cntr_no = cntr_no
      @default_main_params = {
        'searchType' => 'cont',
        'SEARCH_NUMBER' => cntr_no
      }
      @params = {}
      @cookie = nil
      @user_token = ''
    end

    def check_valid_reponse!(res)
      if res.body.include?('API integration, please contact helpdesk@cargosmart.com')
        raise StandardError, 'Blocked by cargosmart! Cannot crawl'
      elsif res.body.include?('This website is blocked')
        raise StandardError, 'Blocked by cargosmart! Cannot crawl'
      end
    end
  
  end
end
