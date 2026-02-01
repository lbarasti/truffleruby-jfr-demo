# frozen_string_literal: true

class QueueLimiter
  def initialize(max_inflight, max_wait_ms, max_queue_depth)
    @max_inflight = max_inflight
    @max_wait_seconds = max_wait_ms / 1000.0
    @max_queue_depth = max_queue_depth
    @tokens = SizedQueue.new(max_inflight)
    max_inflight.times { @tokens << :token }
    @waiting = 0
  end

  # Returns :acquired, :queue_full, or :timeout
  # Note: @waiting is approximate (no mutex) - SizedQueue provides real synchronization
  def acquire
    return :queue_full if @waiting >= @max_queue_depth

    @waiting += 1
    begin
      token = @tokens.pop(false, timeout: @max_wait_seconds)
      token.nil? ? :timeout : :acquired
    rescue ThreadError
      :timeout
    ensure
      @waiting -= 1
    end
  end

  def release
    @tokens.push(:token, true)
  rescue ThreadError
    # Ignore over-release to avoid blocking.
  end

  def inflight
    @max_inflight - @tokens.size
  end

  def available
    @tokens.size
  end

  def waiting
    @waiting
  end

  def queue_depth
    @max_queue_depth
  end
end
