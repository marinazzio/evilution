# frozen_string_literal: true

require_relative "../../rspec"
require_relative "internals"

class Evilution::Integration::RSpec::StateGuard::ReporterArrays
  IVARS = %i[@examples @failed_examples @pending_examples].freeze

  def snapshot
    reporter = Evilution::Integration::RSpec::StateGuard::Internals.config_ivar(:@reporter)
    return nil unless reporter

    IVARS.each_with_object({}) do |ivar, acc|
      next unless reporter.instance_variable_defined?(ivar)

      arr = reporter.instance_variable_get(ivar)
      acc[ivar] = arr.length if arr.is_a?(Array)
    end
  end

  def release(lengths)
    return unless lengths

    reporter = Evilution::Integration::RSpec::StateGuard::Internals.config_ivar(:@reporter)
    return unless reporter

    lengths.each do |ivar, length|
      arr = reporter.instance_variable_get(ivar)
      arr.slice!(length..) if arr.is_a?(Array) && arr.length > length
    end
  end
end
