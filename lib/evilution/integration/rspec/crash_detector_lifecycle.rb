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
      ::RSpec.configuration.add_formatter(@detector)
    end
    @detector
  end
end
