# frozen_string_literal: true

require_relative "../cli"

class Evilution::Reporter::CLI::Pct
  def format(value)
    Kernel.format("%.2f%%", value * 100)
  end
end
