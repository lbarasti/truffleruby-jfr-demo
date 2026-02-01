# frozen_string_literal: true

# Metrics collector module with thread-safe ring buffers
module Metrics
  MAX_ENTRIES = 60
  @data = {
    cpu: [],
    memory: [],
    requests: [],
    gc: [],
    queue: []
  }
  @queue_rejections_full = 0
  @queue_rejections_timeout = 0
  @queue_wait_total_ms = 0
  @queue_wait_count = 0
  @mutex = Mutex.new

  class << self
    def data
      @mutex.synchronize do
        # Return a snapshot copy for thread-safe reading
        {
          cpu: @data[:cpu].dup,
          memory: @data[:memory].dup,
          requests: @data[:requests].dup,
          gc: @data[:gc].dup,
          queue: @data[:queue].dup
        }
      end
    end

    def add_cpu(time, percent)
      @mutex.synchronize do
        @data[:cpu] << { time: time, percent: percent }
        @data[:cpu].shift if @data[:cpu].size > MAX_ENTRIES
      end
    end

    def add_memory(time, system_percent, process_mb)
      @mutex.synchronize do
        @data[:memory] << { time: time, system_percent: system_percent, process_mb: process_mb }
        @data[:memory].shift if @data[:memory].size > MAX_ENTRIES
      end
    end

    def add_gc(time, count, delta, heap_live_slots, total_allocated_objects)
      @mutex.synchronize do
        @data[:gc] << {
          time: time,
          count: count,
          delta: delta,
          heap_live_slots: heap_live_slots,
          total_allocated_objects: total_allocated_objects
        }
        @data[:gc].shift if @data[:gc].size > MAX_ENTRIES
      end
    end

    def add_request(time, duration_ms)
      @mutex.synchronize do
        @data[:requests] << { time: time, duration_ms: duration_ms }
        @data[:requests].shift if @data[:requests].size > MAX_ENTRIES
      end
    end

    def record_queue_wait(wait_ms)
      @mutex.synchronize do
        @queue_wait_total_ms += wait_ms
        @queue_wait_count += 1
      end
    end

    def record_queue_reject(reason = :timeout)
      @mutex.synchronize do
        case reason
        when :queue_full
          @queue_rejections_full += 1
        else
          @queue_rejections_timeout += 1
        end
      end
    end

    def add_queue_sample(time, inflight, available, waiting = 0)
      @mutex.synchronize do
        avg_wait_ms = if @queue_wait_count.positive?
                        (@queue_wait_total_ms / @queue_wait_count.to_f).round(1)
                      else
                        0
                      end

        @data[:queue] << {
          time: time,
          inflight: inflight,
          available: available,
          waiting: waiting,
          rejected_full: @queue_rejections_full,
          rejected_timeout: @queue_rejections_timeout,
          avg_wait_ms: avg_wait_ms
        }
        @data[:queue].shift if @data[:queue].size > MAX_ENTRIES

        @queue_rejections_full = 0
        @queue_rejections_timeout = 0
        @queue_wait_total_ms = 0
        @queue_wait_count = 0
      end
    end
  end
end
