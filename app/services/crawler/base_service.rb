module Crawler
  class BaseService
    include Executable

    SERVICE_NAME = 'BaseService'.freeze

    ERR_CNTR_NO_INFO = 'Cannot get container info'.freeze
    ERR_REACH_MAX_RETRY = 'Reach maximum retry times'.freeze

    def initialize(cntr_no)
      @cntr_no = cntr_no
    end

    def execute
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    private

    def parse_time(event)
      Time.parse(event).strftime('%Y-%m-%d %H:%M:%S')
    end
  end

  class Error < StandardError
  end
end
