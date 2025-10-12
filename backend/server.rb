# frozen_string_literal: true

require 'socket'
require 'uri'
require 'stringio'
require 'rack'

require_relative 'app'

module UpdateViewer
  class Server
    DEFAULT_HOST = '0.0.0.0'
    DEFAULT_PORT = 9292
    DEFAULT_ALLOWED_METHODS = %w[GET HEAD POST OPTIONS]
    DEFAULT_ALLOWED_HEADERS = %w[Content-Type Authorization Accept]

    def initialize(app = UpdateViewer::App.freeze.app, host: ENV.fetch('HOST', DEFAULT_HOST), port: (ENV['PORT'] || DEFAULT_PORT).to_i)
      @app = app
      @host = host
      @port = port
      @allowed_origins = (ENV['ALLOWED_ORIGINS']&.split(',') || ['*']).map(&:strip)
      @logger = UpdateViewer.logger
    end

    def start
      TCPServer.open(host, port) do |server|
        logger.info("[server] Listening on http://#{display_host}:#{port}")
        loop do
          client = server.accept
          Thread.new { handle_client(client) }
        end
      end
    rescue Errno::EACCES, Errno::EADDRINUSE, Errno::EPERM => e
      logger.fatal("[server] Failed to bind to #{host}:#{port} - #{e.class}: #{e.message}")
      exit 1
    end

    private

    attr_reader :app, :host, :port, :logger

    def handle_client(socket)
      method = request_target = http_version = nil
      request_line = socket.gets
      return socket.close unless request_line

      method, request_target, http_version = request_line.split
      unless method && request_target && http_version
        logger.warn("[server] Malformed request line: #{request_line.strip}")
        return respond_with_bad_request(socket)
      end

      headers = read_headers(socket)
      body = read_body(socket, headers)
      origin = headers['origin']

      if method == 'OPTIONS'
        respond_with_preflight(socket, origin, headers)
        return
      end

      env = build_env(method, request_target, headers, body, socket)

      body_enum = nil
      status, response_headers, body_enum = app.call(env)
      response_headers = apply_cors_headers(response_headers, origin)

      write_response(socket, status, response_headers, body_enum)
    rescue StandardError => e
      logger.error(
        "[server] Error handling request #{method} #{request_target} - #{e.class}: #{e.message}\n#{Array(e.backtrace).join("\n")}"
      )
      respond_with_internal_error(socket)
    ensure
      body_enum&.close if defined?(body_enum) && body_enum.respond_to?(:close)
      socket.close unless socket.closed?
    end

    def read_headers(socket)
      headers = {}
      while (line = socket.gets)
        line = line.strip
        break if line.empty?

        key, value = line.split(':', 2)
        headers[key.downcase] = value&.strip if key && value
      end
      headers
    end

    def read_body(socket, headers)
      length = headers['content-length']&.to_i
      return '' unless length&.positive?

      socket.read(length) || ''
    end

    def build_env(method, request_target, headers, body, socket)
      uri = URI.parse(request_target)
      path = uri.path.empty? ? '/' : uri.path

      {
        'REQUEST_METHOD' => method,
        'SCRIPT_NAME' => '',
        'PATH_INFO' => path,
        'QUERY_STRING' => uri.query.to_s,
        'SERVER_NAME' => host,
        'SERVER_PORT' => port.to_s,
        'rack.version' => Rack::VERSION,
        'rack.url_scheme' => 'http',
        'rack.input' => StringIO.new(body),
        'rack.errors' => $stderr,
        'rack.multithread' => true,
        'rack.multiprocess' => false,
        'rack.run_once' => false,
        'REMOTE_ADDR' => socket_peer_address(headers, socket)
      }.merge(rack_headers(headers))
    end

    def rack_headers(headers)
      headers.each_with_object({}) do |(key, value), memo|
        header_key = "HTTP_#{key.tr('-', '_').upcase}"
        memo[header_key] = value
      end
    end

    def socket_peer_address(headers, socket)
      headers['x-forwarded-for'] || headers['forwarded'] || socket.peeraddr(false)[3]
    end

    def write_response(socket, status, headers, body_enum)
      reason = Rack::Utils::HTTP_STATUS_CODES[status] || 'OK'
      socket.write "HTTP/1.1 #{status} #{reason}\r\n"

      headers = headers.dup
      headers['Connection'] ||= 'close'

      headers.each do |key, value|
        if value.is_a?(Array)
          value.each { |v| socket.write "#{key}: #{v}\r\n" }
        else
          socket.write "#{key}: #{value}\r\n"
        end
      end
      socket.write "\r\n"

      body_enum.each { |chunk| socket.write(chunk) }
    end

    def respond_with_bad_request(socket)
      socket.write "HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
    end

    def respond_with_internal_error(socket)
      socket.write "HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
    end

    def respond_with_preflight(socket, origin, request_headers)
      headers = {
        'Access-Control-Allow-Origin' => allow_origin(origin),
        'Access-Control-Allow-Methods' => DEFAULT_ALLOWED_METHODS.join(', '),
        'Access-Control-Allow-Headers' => (request_headers['access-control-request-headers'] || DEFAULT_ALLOWED_HEADERS.join(', ')),
        'Access-Control-Max-Age' => '600',
        'Connection' => 'close',
        'Content-Length' => '0'
      }
      headers['Vary'] = 'Origin'

      socket.write "HTTP/1.1 204 No Content\r\n"
      headers.each { |key, value| socket.write "#{key}: #{value}\r\n" }
      socket.write "\r\n"
    end

    def apply_cors_headers(headers, origin)
      headers = headers.dup
      headers['Access-Control-Allow-Origin'] = allow_origin(origin)
      headers['Access-Control-Allow-Credentials'] = 'false'
      headers['Access-Control-Expose-Headers'] ||= 'Content-Length'
      headers['Vary'] = Array(headers['Vary']).push('Origin').uniq.join(', ')
      headers
    end

    def allow_origin(origin)
      return origin if origin && (allowed_origins.include?('*') || allowed_origins.include?(origin))

      allowed_origins.first || '*'
    end

    def display_host
      host == '0.0.0.0' ? 'localhost' : host
    end

    attr_reader :allowed_origins
  end
end

if $PROGRAM_NAME == __FILE__
  UpdateViewer::Server.new.start
end
