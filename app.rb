# frozen_string_literal: true

require 'sinatra'
require 'json'

configure do
  set :port, ENV.fetch('PORT', 8080).to_i
  set :bind, '0.0.0.0'
  set :host_authorization, permitted_hosts: []
end

# Metrics collector module with object pooling
module Metrics
  MAX_ENTRIES = 60
  @shutdown = false
  @data = {
    cpu: [],
    memory: [],
    requests: [],
    gc: []
  }

  # Pre-allocate reusable entry hashes to reduce allocations
  @cpu_entry = { time: nil, percent: nil }
  @memory_entry = { time: nil, system_percent: nil, process_mb: nil }
  @gc_entry = { time: nil, count: nil, delta: nil, heap_live_slots: nil, total_allocated_objects: nil }

  class << self
    attr_accessor :shutdown, :data

    def add_cpu(time, percent)
      @data[:cpu] << { time: time, percent: percent }
      @data[:cpu].shift if @data[:cpu].size > MAX_ENTRIES
    end

    def add_memory(time, system_percent, process_mb)
      @data[:memory] << { time: time, system_percent: system_percent, process_mb: process_mb }
      @data[:memory].shift if @data[:memory].size > MAX_ENTRIES
    end

    def add_gc(time, count, delta, heap_live_slots, total_allocated_objects)
      @data[:gc] << {
        time: time,
        count: count,
        delta: delta,
        heap_live_slots: heap_live_slots,
        total_allocated_objects: total_allocated_objects
      }
      @data[:gc].shift if @data[:gc].size > MAX_ENTRIES
    end

    def add_request(time, duration_ms)
      @data[:requests] << { time: time, duration_ms: duration_ms }
      @data[:requests].shift if @data[:requests].size > MAX_ENTRIES
    end
  end
end

# Handle CTRL-C gracefully
trap('INT') { Metrics.shutdown = true; exit }
trap('TERM') { Metrics.shutdown = true; exit }

# Prime checking (intentionally inefficient for CPU demo)
def prime?(n)
  return false if n < 2
  (2..Math.sqrt(n).to_i).none? { |i| n % i == 0 }
end

# System metrics collector using /proc (Linux) or shell commands (macOS)
module SystemMetrics
  # Cache platform detection at load time
  @is_linux = File.exist?('/proc/stat')
  @prev_idle = 0
  @prev_total = 0

  # Pre-compile regex patterns
  CPU_USAGE_REGEX = /(\d+\.?\d*)% user.*?(\d+\.?\d*)% sys/
  PAGES_FREE_REGEX = /Pages free:\s+(\d+)/
  PAGES_ACTIVE_REGEX = /Pages active:\s+(\d+)/
  PAGES_INACTIVE_REGEX = /Pages inactive:\s+(\d+)/
  PAGES_SPECULATIVE_REGEX = /Pages speculative:\s+(\d+)/
  PAGES_WIRED_REGEX = /Pages wired down:\s+(\d+)/

  class << self
    def cpu_percent
      @is_linux ? cpu_percent_linux : cpu_percent_macos
    end

    def memory_percent
      @is_linux ? memory_percent_linux : memory_percent_macos
    end

    def process_memory_mb
      @is_linux ? process_memory_linux : process_memory_macos
    end

    private

    # Linux: read from /proc
    def cpu_percent_linux
      line = File.read('/proc/stat', 256).lines.first
      parts = line.split
      idle = parts[4].to_i
      total = parts[1..].sum(&:to_i)

      diff_idle = idle - @prev_idle
      diff_total = total - @prev_total

      @prev_idle = idle
      @prev_total = total

      return 0.0 if diff_total == 0
      ((1.0 - diff_idle.to_f / diff_total) * 100).round(2)
    end

    def memory_percent_linux
      content = File.read('/proc/meminfo', 512)
      total = content[/MemTotal:\s+(\d+)/, 1].to_f
      available = content[/MemAvailable:\s+(\d+)/, 1].to_f

      return 0.0 if total == 0
      ((1.0 - available / total) * 100).round(2)
    end

    def process_memory_linux
      content = File.read('/proc/self/status', 1024)
      kb = content[/VmRSS:\s+(\d+)/, 1].to_f
      (kb / 1024).round(1)
    end

    # macOS: shell out to system commands
    def cpu_percent_macos
      output = `top -l 1 -s 0 2>/dev/null | grep "CPU usage"`
      match = output.match(CPU_USAGE_REGEX)
      return 0.0 unless match
      (match[1].to_f + match[2].to_f).round(2)
    rescue
      0.0
    end

    def memory_percent_macos
      output = `vm_stat 2>/dev/null`
      free = output.match(PAGES_FREE_REGEX)[1].to_i
      active = output.match(PAGES_ACTIVE_REGEX)[1].to_i
      inactive = output.match(PAGES_INACTIVE_REGEX)[1].to_i
      speculative = output.match(PAGES_SPECULATIVE_REGEX)&.[](1).to_i || 0
      wired = output.match(PAGES_WIRED_REGEX)[1].to_i

      total = free + active + inactive + speculative + wired
      used = active + wired
      return 0.0 if total == 0
      (used.to_f / total * 100).round(2)
    rescue
      0.0
    end

    def process_memory_macos
      output = `ps -o rss= -p #{Process.pid} 2>/dev/null`
      (output.to_f / 1024).round(1)
    rescue
      0.0
    end
  end
end

# Timestamp format string (frozen)
TIME_FORMAT = '%H:%M:%S'

# Start system metrics collector
def start_metrics_collector
  # Prime the CPU calculation
  SystemMetrics.cpu_percent
  prev_gc_count = GC.count

  Thread.new do
    until Metrics.shutdown
      # Format timestamp once per cycle
      timestamp = Time.now.strftime(TIME_FORMAT)

      # Collect all metrics with shared timestamp
      Metrics.add_cpu(timestamp, SystemMetrics.cpu_percent)

      Metrics.add_memory(
        timestamp,
        SystemMetrics.memory_percent,
        SystemMetrics.process_memory_mb
      )

      # GC stats
      gc_count = GC.count
      gc_stats = GC.stat
      Metrics.add_gc(
        timestamp,
        gc_count,
        gc_count - prev_gc_count,
        gc_stats[:heap_live_slots] || 0,
        gc_stats[:total_allocated_objects] || 0
      )
      prev_gc_count = gc_count

      sleep 1
    end
  end

  puts 'System metrics collector started'
end

start_metrics_collector

# Routes
get '/' do
  redirect '/dashboard'
end

get '/compute' do
  content_type :json

  n = (params[:n] || 10_000).to_i
  n = [[n, 100].max, 100_000].min

  start = Time.now
  count = (2..n).count { |x| prime?(x) }
  duration = ((Time.now - start) * 1000).round(2)

  Metrics.add_request(Time.now.strftime(TIME_FORMAT), duration)

  { result: count, n: n, duration_ms: duration }.to_json
end

get '/dashboard' do
  erb :dashboard
end

get '/events' do
  content_type 'text/event-stream'
  cache_control :no_cache
  headers 'Connection' => 'keep-alive'

  stream(:keep_open) do |out|
    loop do
      begin
        out << "data: #{Metrics.data.to_json}\n\n"
        sleep 1
      rescue IOError
        break
      end
    end
  end
end

get '/health' do
  content_type :json
  {
    status: 'ok',
    ruby: RUBY_DESCRIPTION,
    memory_mb: SystemMetrics.process_memory_mb
  }.to_json
end
