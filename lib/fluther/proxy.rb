require 'rack/request'
require 'em-http-request'

module Fluther

class Proxy
  def initialize( app, prefix )
    @app, @prefix = app, prefix
    @prefix = "/#{@prefix}"  unless @prefix.starts_with?('/')
  end

  def call( env )
    return @app.call( env )  unless env['PATH_INFO'] =~ %r{^#{@prefix}}
    @in_req = Rack::Request.new env

    @user = {}
    if user = @in_req.env['warden'].authenticate rescue nil
      @user = Hash[ Fluther::Config.user_fields.map { |dest, src|  [dest, user.send(src).to_s] } ]
    end

    exec_request
  end

protected
  def build_request
    params = @in_req.params.dup.update(
      :fed_key => Fluther::Config.app_key
    )
    params[:fed_sessionid] = @in_req.cookies['fed_sessionid']  if @in_req.cookies['fed_sessionid']
    if @user.present?
      params[:fed_uid] = @user[:id].to_s
      params[:fed_username] = @user[:name].to_s
      params[:fed_email] = @user[:email].to_s
    end

    options = {
      :redirects => 0,
      :timeout => 10,
      :head => {
        'User-Agent' => "Fluther Federated Client #{Fluther::ClientVersion} (Ruby)",
        'X-Forwarded-For' => @in_req.env['REMOTE_ADDR'],
        'X-Forwarded-Host' => @in_req.env['HTTP_HOST'],
      }
    }
    options[:head]['X-Requested-With'] = @in_req.env['HTTP_X_REQUESTED_WITH']  if @in_req.env['HTTP_X_REQUESTED_WITH']
    options[@in_req.post? ? :body : :query] = params

    path = @in_req.path.sub( %r{^#{@prefix}}, '' )
    path = '/' + path  unless path.starts_with?('/')
    url = "#{@in_req.scheme}://#{Fluther::Config.fluther_host}#{path}"

Rails.logger.debug @in_req.request_method
Rails.logger.debug url
Rails.logger.debug options

    EventMachine::HttpRequest.new( url ).send( @in_req.request_method.downcase.to_sym, options )
  end

  def exec_request
    result = nil
    em_running = EM.reactor_running?
    EM.run  do
      fluther = build_request
      fluther.callback do
        result = handle_response fluther

        if em_running
          # async
          @in_req.env['async.callback'].call result
        else
          # sync
          EM.stop
        end
      end
    end

    if em_running
      # async
      throw :async
    else
      # sync
      result
    end
  end

  def handle_response( fluther )
Rails.logger.debug fluther.response_header.status
Rails.logger.debug fluther.response_header

    type_header = fluther.response_header['CONTENT_TYPE']
    content_type = type_header.split(';')[0] || 'text/html'

    result = if [301, 302].include?( fluther.response_header.status )
      [ fluther.response_header.status, {'Location' => fluther.response_header['LOCATION']}, ['Redirecting'] ]

    elsif @in_req.xhr? || (content_type != 'text/html')
      [ fluther.response_header.status, {'Content-Type' => type_header}, [fluther.response] ]

    else
      fluther.response.html_safe  if fluther.response.respond_to?(:html_safe)
      @in_req.env['fluther.response'] = fluther.response
      @in_req.env['fluther.title']  = fluther.response_header['FLUTHER_TITLE']  if fluther.response_header['FLUTHER_TITLE']
      @in_req.env['fluther.header'] = fluther.response_header['FLUTHER_HEADER']  if fluther.response_header['FLUTHER_HEADER']
      @app.call @in_req.env
    end
    result
  end
end

end
