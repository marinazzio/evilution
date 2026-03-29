# frozen_string_literal: true

require_relative "../reporter"

class Evilution::Reporter::ProgressBar
  attr_reader :total, :width, :completed, :killed, :survived

  def initialize(total:, output: $stdout, width: 30)
    @total = total
    @output = output
    @width = width
    @completed = 0
    @killed = 0
    @survived = 0
    @tty = self.class.tty?(output)
    @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def tick(status:)
    @completed += 1
    @killed += 1 if status == :killed
    @survived += 1 if status == :survived
    render
  end

  def render
    line = "#{bar_string} #{stats_string} | #{time_string}"
    if @tty
      @output.print("\r#{line}")
    else
      @output.puts(line)
    end
  end

  def finish
    render
    @output.print("\n") if @tty
  end

  def self.tty?(io)
    io.respond_to?(:tty?) && io.tty?
  end

  private

  def bar_string
    fraction = @total.positive? ? @completed.to_f / @total : 0
    raw_filled = (fraction * @width).to_i
    filled = raw_filled.clamp(0, @width)

    interior = if filled <= 0
                 " " * @width
               elsif filled >= @width
                 "#{"=" * (@width - 1)}>"
               else
                 "#{"=" * (filled - 1)}>#{" " * (@width - filled)}"
               end

    "[#{interior}]"
  end

  def stats_string
    "#{@completed}/#{@total} mutations | #{@killed} killed | #{@survived} survived"
  end

  def time_string
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
    remaining = estimate_remaining(elapsed)
    "#{format_time(elapsed)} elapsed | ~#{format_time(remaining)} remaining"
  end

  def estimate_remaining(elapsed)
    return 0 unless @completed.positive?

    remaining = (@total - @completed) * (elapsed / @completed)
    [remaining, 0].max
  end

  def format_time(seconds)
    mins = (seconds / 60).to_i
    secs = (seconds % 60).to_i
    format("%<mins>02d:%<secs>02d", mins: mins, secs: secs)
  end
end
