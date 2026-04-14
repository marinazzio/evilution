# frozen_string_literal: true

require_relative "../memory"
require_relative "../parallel/pool"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass

class Evilution::Runner::Diagnostics
  def initialize(config, stderr: $stderr)
    @config = config
    @stderr = stderr
  end

  def log_memory(phase, context = nil)
    return unless verbose?

    rss = Evilution::Memory.rss_mb
    return unless rss

    gc = gc_stats_string
    msg = format("[memory] %<phase>s: %<rss>.1f MB", phase: phase, rss: rss)
    ctx = [context, gc].compact.join(", ")
    msg += " (#{ctx})" unless ctx.empty?
    stderr.write("#{msg}\n")
  end

  def log_progress(current, status)
    return unless text_tty?

    stderr.write("mutation #{current} #{status}\n")
  end

  def log_mutation_diagnostics(result)
    return unless verbose?

    parts = []
    parts << format("child_rss: %<mb>.1f MB", mb: result.child_rss_kb / 1024.0) if result.child_rss_kb

    if result.memory_delta_kb
      sign = result.memory_delta_kb.negative? ? "" : "+"
      parts << format("delta: %<sign>s%<mb>.1f MB", sign: sign, mb: result.memory_delta_kb / 1024.0)
    end

    parts << gc_stats_string

    stderr.write("[verbose] #{result.mutation}: #{parts.join(", ")}\n") unless parts.empty?

    log_mutation_error(result) if result.error?
  end

  def log_worker_stats(stats)
    return unless verbose? && stats.any?

    stats.each do |stat|
      pct = format("%.1f", stat.utilization * 100)
      stderr.write("[verbose] worker #{stat.pid}: #{stat.items_completed} items, utilization #{pct}%\n")
    end
  end

  def aggregate_worker_stats(stats)
    return stats if stats.empty?

    stats.group_by(&:pid).map do |pid, entries|
      Evilution::Parallel::WorkQueue::WorkerStat.new(
        pid,
        entries.sum(&:items_completed),
        entries.sum(&:busy_time),
        entries.sum(&:wall_time)
      )
    end
  end

  private

  attr_reader :config, :stderr

  def verbose?
    config.verbose && !config.quiet
  end

  def text_tty?
    !config.quiet && config.text? && stderr.tty?
  end

  def log_mutation_error(result)
    header = "[verbose] #{result.mutation}: error"
    header += " #{result.error_class}" if result.error_class
    header += ": #{result.error_message}" if result.error_message
    stderr.write("#{header}\n")

    Array(result.error_backtrace).first(5).each do |line|
      stderr.write("[verbose]   #{line}\n")
    end
  end

  def gc_stats_string
    stats = GC.stat
    format(
      "heap_live_slots: %<live>d, allocated: %<alloc>d, freed: %<freed>d",
      live: stats[:heap_live_slots],
      alloc: stats[:total_allocated_objects],
      freed: stats[:total_freed_objects]
    )
  end
end
