# frozen_string_literal: true

require "stringio"
require_relative "../rspec"
require_relative "../crash_detector"

class Evilution::Integration::RSpec::CrashDetectorLifecycle
  def current
    if @detector
      @detector.reset
    else
      @detector = Evilution::Integration::CrashDetector.new(StringIO.new)
    end
    @detector
  end

  # The run rebuilds RSpec's formatter loader so its formatters are bound to the
  # run's own streams (EV-m6xc / GH #1627), which drops any formatter registered
  # before it — the detector included. It is registered per run instead.
  def register
    detector = current
    ::RSpec.configuration.add_formatter(detector)
    detector
  end
end
