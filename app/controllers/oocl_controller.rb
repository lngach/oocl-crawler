class OoclController < ApplicationController
  def index
    containers = params[:containers]
    if containers.present?
      crawler = Crawler::OoclService.new(containers)
      crawled = crawler.execute
      if crawled[:success] && !crawled[containers].empty?
        json_response(crawled, :ok)
      elsif crawled[:success] && crawled[:containers].empty?
        json_response({ success: crawled[:success], message: "Containers not found #{containers.join(', ')}" }, :not_found)
      else
        json_response({ success: crawled[:success], message: crawled[:message] }, :bad_request)
      end
    else
      json_response({ success: false, message: 'Missing params containers' }, :bad_request)
    end
  end
end
