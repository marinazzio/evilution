# frozen_string_literal: true

require_relative "../line_formatters"
require_relative "../pct"

class Evilution::Reporter::CLI::LineFormatters::Efficiency
  def initialize(pct: Evilution::Reporter::CLI::Pct.new)
    @pct = pct
  end

  def format(summary)
    return nil unless summary.duration.positive?

    pct = @pct.format(summary.efficiency)
    rate = Kernel.format("%.2f", summary.mutations_per_second)
    "Efficiency: #{pct} killtime, #{rate} mutations/s"
  end
end
