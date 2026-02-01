# frozen_string_literal: true

class QueueLimiter
  def initialize(max_inflight, max_wait_ms)
    @max_inflight = max_inflight
    @max_wait_seconds = max_wait_ms / 1000.0
    @tokens = SizedQueue.new(max_inflight)
    max_inflight.times { @tokens << :token }
  end

  def acquire
    token = @tokens.pop(false, timeout: @max_wait_seconds)
    !token.nil?
  rescue ThreadError
    false
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
end
