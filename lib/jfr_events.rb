# frozen_string_literal: true

# JFR Event streaming module
# Uses TruffleRuby's JFR streaming API (requires custom native image build with JFR support)
module JFREvents
  MAX_EVENTS = 200
  TIME_FORMAT = '%H:%M:%S'

  @events = []
  @event_counter = 0  # Monotonically increasing counter
  @mutex = Mutex.new
  @streaming = false
  @stream = nil
  @request_correlation = {} # Maps request_id -> [jfr_events]

  # Event types we're interested in
  WATCHED_EVENTS = %w[
    jdk.GarbageCollection
    jdk.GCPhasePause
    jdk.CPULoad
    jdk.ThreadStart
    jdk.ThreadEnd
    jdk.JavaMonitorEnter
    jdk.JavaMonitorWait
  ].freeze

  class << self
    attr_reader :events, :streaming

    def start_streaming
      return if @streaming

      begin
        recording_stream_class = Java.type('jdk.jfr.consumer.RecordingStream')
        @stream = recording_stream_class.new

        # Enable and register callbacks for each event type
        WATCHED_EVENTS.each do |event_type|
          @stream.enable(event_type)
          @stream.onEvent(event_type) do |event|
            begin
              handle_jfr_event(event_type, event)
            rescue => e
              puts "JFR event handler error (#{event_type}): #{e.message}"
            end
          end
        end

        @stream.startAsync
        @streaming = true
        puts "JFR streaming started (#{WATCHED_EVENTS.size} event types enabled)"
      rescue NameError => e
        puts "JFR streaming not available: #{e.message}"
        puts "Run with custom TruffleRuby native image that has JFR consumer classes exposed"
      rescue => e
        puts "JFR streaming failed: #{e.class} - #{e.message}"
      end
    end

    def stop_streaming
      return unless @streaming && @stream

      @stream.close
      @streaming = false
      puts 'JFR streaming stopped'
    end

    private

    def handle_jfr_event(event_type, event)
      data = extract_event_data(event_type, event)
      duration = begin
        event.getDuration.toMillis
      rescue
        nil
      end

      add_event(
        type: event_type,
        time: Time.now.strftime(TIME_FORMAT),
        duration_ms: duration,
        data: data
      )
    end

    def extract_event_data(event_type, event)
      case event_type
      when 'jdk.GarbageCollection'
        { cause: safe_get_string(event, 'cause'), name: safe_get_string(event, 'name') }
      when 'jdk.GCPhasePause'
        { name: safe_get_string(event, 'name') }
      when 'jdk.CPULoad'
        { jvmUser: safe_get_float(event, 'jvmUser'), jvmSystem: safe_get_float(event, 'jvmSystem') }
      when 'jdk.ThreadStart', 'jdk.ThreadEnd'
        { thread: safe_get_string(event, 'thread') }
      when 'jdk.JavaMonitorEnter', 'jdk.JavaMonitorWait'
        { monitorClass: safe_get_string(event, 'monitorClass') }
      else
        {}
      end
    rescue => e
      { error: e.message }
    end

    def safe_get_string(event, field)
      event.getString(field)
    rescue
      nil
    end

    def safe_get_float(event, field)
      event.getFloat(field)&.round(4)
    rescue
      nil
    end

    def safe_get_long(event, field)
      event.getLong(field)
    rescue
      nil
    end

    public

    def add_event(type:, time: nil, duration_ms: nil, data: {}, request_id: nil)
      timestamp = time || Time.now.strftime(TIME_FORMAT)

      @mutex.synchronize do
        @event_counter += 1

        event = {
          id: @event_counter,
          type: type,
          time: timestamp,
          duration_ms: duration_ms,
          data: data,
          request_id: request_id
        }.compact

        @events << event
        @events.shift if @events.size > MAX_EVENTS

        # Track correlation with requests
        if request_id
          @request_correlation[request_id] ||= []
          @request_correlation[request_id] << event
        end
      end
    end

    def events_since(last_id)
      @mutex.synchronize do
        return @events.dup if last_id.nil? || last_id.zero?

        # Find events with id greater than last_id
        @events.select { |e| e[:id] > last_id }
      end
    end

    def events_for_request(request_id)
      @mutex.synchronize do
        @request_correlation[request_id] || []
      end
    end

    def current_event_id
      @mutex.synchronize { @event_counter }
    end

    # Emit custom app event
    def emit(type, duration_ms: nil, request_id: nil, **data)
      add_event(
        type: "app.#{type}",
        duration_ms: duration_ms,
        data: data,
        request_id: request_id
      )
    end

    # Track an image job with start/end events and timing
    # Note: Requires Metrics module to be loaded
    def track_job(job, **params)
      request_id = "#{job}-#{Time.now.to_f}"
      emit('ImageJobStart', request_id: request_id, job: job, **params)

      start = Time.now
      result = yield
      duration = ((Time.now - start) * 1000).round(2)

      emit('ImageJobEnd', request_id: request_id, job: job, duration_ms: duration, **params)
      Metrics.add_request(Time.now.strftime(TIME_FORMAT), duration)

      result
    end
  end
end
