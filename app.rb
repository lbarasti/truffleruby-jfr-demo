require 'sinatra'
require 'json'

configure do
  set :port, ENV.fetch('PORT', 8080).to_i
  set :bind, '0.0.0.0'
  set :host_authorization, permitted_hosts: []
end

# Metrics collector module
module Metrics
  MAX_ENTRIES = 60
  @shutdown = false
  @data = {
    cpu: [],
    memory: [],
    requests: []
  }

  class << self
    attr_accessor :shutdown, :data

    def add(type, entry)
      @data[type] << entry
      @data[type].shift if @data[type].size > MAX_ENTRIES
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
  @prev_idle = 0
  @prev_total = 0

  class << self
    def cpu_percent
      if File.exist?('/proc/stat')
        cpu_percent_linux
      else
        cpu_percent_macos
      end
    end

    def memory_percent
      if File.exist?('/proc/meminfo')
        memory_percent_linux
      else
        memory_percent_macos
      end
    end

    def process_memory_mb
      if File.exist?('/proc/self/status')
        process_memory_linux
      else
        process_memory_macos
      end
    end

    private

    # Linux: read from /proc
    def cpu_percent_linux
      line = File.readlines('/proc/stat').first
      parts = line.split[1..].map(&:to_i)
      idle = parts[3]
      total = parts.sum

      diff_idle = idle - @prev_idle
      diff_total = total - @prev_total

      @prev_idle = idle
      @prev_total = total

      return 0.0 if diff_total == 0
      ((1.0 - diff_idle.to_f / diff_total) * 100).round(2)
    end

    def memory_percent_linux
      lines = File.readlines('/proc/meminfo')
      total = lines.find { |l| l.start_with?('MemTotal:') }&.split&.[](1).to_f
      available = lines.find { |l| l.start_with?('MemAvailable:') }&.split&.[](1).to_f

      return 0.0 if total == 0
      ((1.0 - available / total) * 100).round(2)
    end

    def process_memory_linux
      line = File.readlines('/proc/self/status').find { |l| l.start_with?('VmRSS:') }
      return 0 unless line
      (line.split[1].to_f / 1024).round(1)
    end

    # macOS: shell out to system commands
    def cpu_percent_macos
      output = `top -l 1 -s 0 2>/dev/null | grep "CPU usage"`
      match = output.match(/(\d+\.?\d*)% user.*?(\d+\.?\d*)% sys/)
      return 0.0 unless match
      (match[1].to_f + match[2].to_f).round(2)
    rescue
      0.0
    end

    def memory_percent_macos
      output = `vm_stat 2>/dev/null`
      free = output.match(/Pages free:\s+(\d+)/)[1].to_i
      active = output.match(/Pages active:\s+(\d+)/)[1].to_i
      inactive = output.match(/Pages inactive:\s+(\d+)/)[1].to_i
      speculative = output.match(/Pages speculative:\s+(\d+)/)[1].to_i rescue 0
      wired = output.match(/Pages wired down:\s+(\d+)/)[1].to_i

      total = free + active + inactive + speculative + wired
      used = active + wired
      return 0.0 if total == 0
      (used.to_f / total * 100).round(2)
    rescue
      0.0
    end

    def process_memory_macos
      pid = Process.pid
      output = `ps -o rss= -p #{pid} 2>/dev/null`
      (output.strip.to_f / 1024).round(1)
    rescue
      0.0
    end
  end
end

# Start system metrics collector
def start_metrics_collector
  # Prime the CPU calculation
  SystemMetrics.cpu_percent

  Thread.new do
    until Metrics.shutdown
      Metrics.add(:cpu, {
        time: Time.now.strftime('%H:%M:%S'),
        percent: SystemMetrics.cpu_percent
      })

      Metrics.add(:memory, {
        time: Time.now.strftime('%H:%M:%S'),
        system_percent: SystemMetrics.memory_percent,
        process_mb: SystemMetrics.process_memory_mb
      })

      sleep 1
    end
  end

  puts "System metrics collector started"
end

start_metrics_collector

# Routes
get '/' do
  redirect '/dashboard'
end

get '/compute' do
  content_type :json

  n = (params[:n] || 10000).to_i
  n = [[n, 100].max, 100000].min

  start = Time.now
  count = (2..n).count { |x| prime?(x) }
  duration = ((Time.now - start) * 1000).round(2)

  Metrics.add(:requests, { time: Time.now.strftime('%H:%M:%S'), duration_ms: duration })

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

