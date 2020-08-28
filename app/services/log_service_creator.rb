class LogServiceCreator
  include Executable

  def initialize(service_name)
    @service_name = service_name
  end

  def execute
    logfile = "#{Rails.root}/log/#{@service_name}.log"
    dir = File.dirname(logfile)
    FileUtils.mkdir_p(dir) unless File.directory?(dir)

    @logfile = Logger.new(logfile)
  end
end
