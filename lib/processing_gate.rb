# frozen_string_literal: true

require 'json'
require 'rack/body_proxy'
require_relative 'metrics'
require_relative 'system_metrics'

class ProcessingGate
  def initialize(app, limiter, max_inflight, max_queue_wait_ms, max_memory_percent, max_queue_depth)
    @app = app
    @limiter = limiter
    @max_inflight = max_inflight
    @max_queue_wait_ms = max_queue_wait_ms
    @max_memory_percent = max_memory_percent
    @max_queue_depth = max_queue_depth
  end

  def call(env)
    result = nil
    return @app.call(env) unless gate_request?(env)

    memory_percent = SystemMetrics.memory_percent
    if memory_percent >= @max_memory_percent
      body = {
        error: 'Server memory high',
        memory_percent: memory_percent,
        max_memory_percent: @max_memory_percent
      }.to_json
      return [503, { 'Content-Type' => 'application/json', 'Retry-After' => '1' }, [body]]
    end

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @limiter.acquire

    case result
    when :queue_full
      Metrics.record_queue_reject(:queue_full)
      body = {
        error: 'Queue full',
        max_queue_depth: @max_queue_depth,
        max_inflight: @max_inflight
      }.to_json
      return [429, { 'Content-Type' => 'application/json', 'Retry-After' => '1' }, [body]]
    when :timeout
      Metrics.record_queue_reject(:timeout)
      body = {
        error: 'Queue timeout',
        max_inflight: @max_inflight,
        retry_after_ms: @max_queue_wait_ms
      }.to_json
      return [429, { 'Content-Type' => 'application/json', 'Retry-After' => '1' }, [body]]
    end

    wait_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    Metrics.record_queue_wait(wait_ms)

    status, headers, body = @app.call(env)
    proxied_body = Rack::BodyProxy.new(body) { @limiter.release }
    [status, headers, proxied_body]
  rescue
    @limiter.release if result == :acquired
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
