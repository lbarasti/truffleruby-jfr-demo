# frozen_string_literal: true

require 'rack/body_proxy'

class ProcessingGate
  def initialize(app, limiter, max_inflight, max_queue_wait_ms)
    @app = app
    @limiter = limiter
    @max_inflight = max_inflight
    @max_queue_wait_ms = max_queue_wait_ms
  end

  def call(env)
    acquired = false
    return @app.call(env) unless gate_request?(env)

    acquired = @limiter.acquire
    unless acquired
      body = {
        error: 'Server busy',
        max_inflight: @max_inflight,
        retry_after_ms: @max_queue_wait_ms
      }.to_json
      return [429, { 'Content-Type' => 'application/json', 'Retry-After' => '1' }, [body]]
    end

    status, headers, body = @app.call(env)
    proxied_body = Rack::BodyProxy.new(body) { @limiter.release }
    [status, headers, proxied_body]
  rescue
    @limiter.release if acquired
    raise
  end

  private

  def gate_request?(env)
    path = env['PATH_INFO']
    method = env['REQUEST_METHOD']
    return true if method == 'POST' && path == '/process'

    method == 'GET' && (path == '/mandelbrot' || path == '/plasma')
  end
end
