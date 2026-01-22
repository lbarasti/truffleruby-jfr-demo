# frozen_string_literal: true

# Metrics collector module with thread-safe ring buffers
module Metrics
  MAX_ENTRIES = 60
  @data = {
    cpu: [],
    memory: [],
    requests: [],
    gc: []
  }
  @mutex = Mutex.new

  class << self
    def data
      @mutex.synchronize do
        # Return a snapshot copy for thread-safe reading
        {
          cpu: @data[:cpu].dup,
          memory: @data[:memory].dup,
          requests: @data[:requests].dup,
          gc: @data[:gc].dup
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
  end
end
