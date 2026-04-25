# frozen_string_literal: true

require_relative "../rspec"

class Evilution::Integration::RSpec::BaselineRunner
  def call(spec_file)
    require "rspec/core"
    spec_dir = File.expand_path("spec")
    $LOAD_PATH.unshift(spec_dir) unless $LOAD_PATH.include?(spec_dir)
    ::RSpec.reset
    status = ::RSpec::Core::Runner.run(
      ["--format", "progress", "--no-color", "--order", "defined", spec_file]
    )
    status.zero?
  end
end
