# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'chunky_png'
require 'base64'

configure do
  set :port, ENV.fetch('PORT', 8080).to_i
  set :bind, '0.0.0.0'
  set :host_authorization, permitted_hosts: []
  # Force Puma to kill connections after 2 seconds on shutdown
  set :server_settings, force_shutdown_after: 2
end

# Metrics collector module with object pooling
module Metrics
  MAX_ENTRIES = 60
  @data = {
    cpu: [],
    memory: [],
    requests: [],
    gc: []
  }

  class << self
    attr_accessor :data

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

# Image processing module using ChunkyPNG
module ImageJobs
  # Generate Mandelbrot fractal - very CPU intensive
  def self.mandelbrot(size: 256, max_iter: 100)
    png = ChunkyPNG::Image.new(size, size, ChunkyPNG::Color::BLACK)

    size.times do |py|
      size.times do |px|
        x0 = (px - size * 0.7) * 3.5 / size
        y0 = (py - size / 2.0) * 3.5 / size

        x = 0.0
        y = 0.0
        iter = 0

        while x * x + y * y <= 4 && iter < max_iter
          xtemp = x * x - y * y + x0
          y = 2 * x * y + y0
          x = xtemp
          iter += 1
        end

        if iter < max_iter
          hue = (iter.to_f / max_iter * 360).to_i
          png[px, py] = hsv_to_rgb(hue, 1.0, 1.0)
        end
      end
    end

    png
  end

  # Generate plasma/noise pattern - CPU intensive
  def self.plasma(size: 256, scale: 0.05)
    png = ChunkyPNG::Image.new(size, size, ChunkyPNG::Color::BLACK)

    size.times do |y|
      size.times do |x|
        # Combine multiple sine waves for plasma effect
        v1 = Math.sin(x * scale)
        v2 = Math.sin(y * scale)
        v3 = Math.sin((x + y) * scale)
        v4 = Math.sin(Math.sqrt(x * x + y * y) * scale)

        v = (v1 + v2 + v3 + v4) / 4.0
        hue = ((v + 1) * 180).to_i

        png[x, y] = hsv_to_rgb(hue, 0.8, 0.9)
      end
    end

    png
  end

  # Apply grayscale filter to uploaded image
  def self.grayscale(png)
    result = ChunkyPNG::Image.new(png.width, png.height)

    png.height.times do |y|
      png.width.times do |x|
        pixel = png[x, y]
        r = ChunkyPNG::Color.r(pixel)
        g = ChunkyPNG::Color.g(pixel)
        b = ChunkyPNG::Color.b(pixel)
        gray = ((r * 0.299 + g * 0.587 + b * 0.114)).to_i
        result[x, y] = ChunkyPNG::Color.rgb(gray, gray, gray)
      end
    end

    result
  end

  # Apply pixelate filter - CPU intensive for small block sizes
  def self.pixelate(png, block_size: 8)
    result = ChunkyPNG::Image.new(png.width, png.height)

    (0...png.height).step(block_size) do |by|
      (0...png.width).step(block_size) do |bx|
        # Average colors in block
        r_sum = g_sum = b_sum = count = 0

        block_size.times do |dy|
          block_size.times do |dx|
            x = bx + dx
            y = by + dy
            next if x >= png.width || y >= png.height

            pixel = png[x, y]
            r_sum += ChunkyPNG::Color.r(pixel)
            g_sum += ChunkyPNG::Color.g(pixel)
            b_sum += ChunkyPNG::Color.b(pixel)
            count += 1
          end
        end

        avg_color = ChunkyPNG::Color.rgb(r_sum / count, g_sum / count, b_sum / count)

        # Fill block with average color
        block_size.times do |dy|
          block_size.times do |dx|
            x = bx + dx
            y = by + dy
            next if x >= png.width || y >= png.height
            result[x, y] = avg_color
          end
        end
      end
    end

    result
  end

  # Edge detection using Sobel operator - CPU intensive
  def self.edge_detect(png)
    result = ChunkyPNG::Image.new(png.width, png.height, ChunkyPNG::Color::BLACK)

    # Sobel kernels
    gx = [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]
    gy = [[-1, -2, -1], [0, 0, 0], [1, 2, 1]]

    (1...png.height - 1).each do |y|
      (1...png.width - 1).each do |x|
        px_gx = py_gy = 0.0

        3.times do |ky|
          3.times do |kx|
            pixel = png[x + kx - 1, y + ky - 1]
            gray = ChunkyPNG::Color.r(pixel) * 0.299 +
                   ChunkyPNG::Color.g(pixel) * 0.587 +
                   ChunkyPNG::Color.b(pixel) * 0.114

            px_gx += gray * gx[ky][kx]
            py_gy += gray * gy[ky][kx]
          end
        end

        magnitude = Math.sqrt(px_gx * px_gx + py_gy * py_gy).to_i
        magnitude = [magnitude, 255].min
        result[x, y] = ChunkyPNG::Color.rgb(magnitude, magnitude, magnitude)
      end
    end

    result
  end

  # HSV to RGB helper
  def self.hsv_to_rgb(h, s, v)
    c = v * s
    x = c * (1 - ((h / 60.0) % 2 - 1).abs)
    m = v - c

    r, g, b = case h
              when 0...60 then [c, x, 0]
              when 60...120 then [x, c, 0]
              when 120...180 then [0, c, x]
              when 180...240 then [0, x, c]
              when 240...300 then [x, 0, c]
              else [c, 0, x]
              end

    ChunkyPNG::Color.rgb(
      ((r + m) * 255).to_i,
      ((g + m) * 255).to_i,
      ((b + m) * 255).to_i
    )
  end
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
    loop do
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

# Generate Mandelbrot fractal
get '/mandelbrot' do
  content_type 'image/png'

  size = (params[:size] || 256).to_i
  size = [[size, 64].max, 512].min
  max_iter = (params[:iter] || 100).to_i
  max_iter = [[max_iter, 50].max, 500].min

  start = Time.now
  png = ImageJobs.mandelbrot(size: size, max_iter: max_iter)
  duration = ((Time.now - start) * 1000).round(2)

  Metrics.add_request(Time.now.strftime(TIME_FORMAT), duration)

  png.to_blob
end

# Generate plasma pattern
get '/plasma' do
  content_type 'image/png'

  size = (params[:size] || 256).to_i
  size = [[size, 64].max, 512].min
  scale = (params[:scale] || 0.05).to_f

  start = Time.now
  png = ImageJobs.plasma(size: size, scale: scale)
  duration = ((Time.now - start) * 1000).round(2)

  Metrics.add_request(Time.now.strftime(TIME_FORMAT), duration)

  png.to_blob
end

# Process uploaded image with filter
post '/process' do
  content_type 'image/png'

  unless params[:image] && params[:image][:tempfile]
    halt 400, { error: 'No image uploaded' }.to_json
  end

  filter = params[:filter] || 'grayscale'

  start = Time.now
  png = ChunkyPNG::Image.from_blob(params[:image][:tempfile].read)

  result = case filter
           when 'grayscale' then ImageJobs.grayscale(png)
           when 'pixelate' then ImageJobs.pixelate(png, block_size: (params[:block_size] || 8).to_i)
           when 'edge' then ImageJobs.edge_detect(png)
           else ImageJobs.grayscale(png)
           end

  duration = ((Time.now - start) * 1000).round(2)
  Metrics.add_request(Time.now.strftime(TIME_FORMAT), duration)

  result.to_blob
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
      out << "data: #{Metrics.data.to_json}\n\n"
      sleep 1
    rescue IOError
      break
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
