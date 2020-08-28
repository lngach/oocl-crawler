module Crawler
  class CrawlerLog
    def initialize(log_name)
      @logfile = LogServiceCreator.execute(log_name)
    end

    def info(message)
      @logfile.info message
    end

    def debug(exception, params)
      @logfile.debug exception, params
    end

    def error(exception, params)
      Airbrake.notify(exception, params)
      @logfile.error exception
    end
  end
end
