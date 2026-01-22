# frozen_string_literal: true

require 'sinatra'
require 'json'

require_relative 'lib/image_jobs'
require_relative 'lib/metrics'
require_relative 'lib/jfr_events'
require_relative 'lib/system_metrics'

configure do
  set :port, ENV.fetch('PORT', 8080).to_i
  set :bind, '0.0.0.0'
  set :host_authorization, permitted_hosts: []
  # Force Puma to kill connections after 2 seconds on shutdown
  set :server_settings, force_shutdown_after: 2
end

# Start system metrics collector
def start_metrics_collector
  # Prime the CPU calculation
  SystemMetrics.cpu_percent
  prev_gc_count = GC.count

  Thread.new do
    loop do
      # Format timestamp once per cycle
      timestamp = Time.now.strftime(JFREvents::TIME_FORMAT)

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
JFREvents.start_streaming

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

  JFREvents.track_job('mandelbrot', size: size, max_iter: max_iter) do
    ImageJobs.mandelbrot(size: size, max_iter: max_iter)
  end.to_blob
end

# Generate plasma pattern
get '/plasma' do
  content_type 'image/png'

  size = (params[:size] || 256).to_i
  size = [[size, 64].max, 512].min
  scale = (params[:scale] || 0.05).to_f

  JFREvents.track_job('plasma', size: size, scale: scale) do
    ImageJobs.plasma(size: size, scale: scale)
  end.to_blob
end

# Process uploaded image with filter
post '/process' do
  content_type 'image/png'

  unless params[:image] && params[:image][:tempfile]
    halt 400, { error: 'No image uploaded' }.to_json
  end

  filter = params[:filter] || 'grayscale'
  png = ChunkyPNG::Image.from_blob(params[:image][:tempfile].read)

  JFREvents.track_job('process', filter: filter, pixels: png.width * png.height) do
    case filter
    when 'grayscale' then ImageJobs.grayscale(png)
    when 'pixelate' then ImageJobs.pixelate(png, block_size: (params[:block_size] || 8).to_i)
    when 'edge' then ImageJobs.edge_detect(png)
    else ImageJobs.grayscale(png)
    end
  end.to_blob
end

get '/dashboard' do
  erb :dashboard
end

get '/events' do
  content_type 'text/event-stream'
  cache_control :no_cache
  headers 'Connection' => 'keep-alive'

  stream(:keep_open) do |out|
    last_jfr_id = 0
    loop do
      # Combine metrics and JFR events in one payload
      jfr_events = []
      current_jfr_id = JFREvents.current_event_id
      if current_jfr_id > last_jfr_id
        jfr_events = JFREvents.events_since(last_jfr_id)
        last_jfr_id = current_jfr_id
      end

      payload = Metrics.data.merge(jfr: jfr_events)
      out << "data: #{payload.to_json}\n\n"
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
