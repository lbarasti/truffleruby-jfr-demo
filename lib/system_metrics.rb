# frozen_string_literal: true

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
