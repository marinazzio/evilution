# frozen_string_literal: true

require_relative "../rspec"

class Evilution::Integration::RSpec::BaselineRunner
  def call(spec_file)
    require "rspec/core"
    # Anchor against PROJECT_ROOT under EV-wqxu sandbox CWD; see
    # FrameworkLoader#add_spec_load_path for rationale.
    base = Evilution.in_isolated_worker? ? Evilution::PROJECT_ROOT : Dir.pwd
    spec_dir = File.expand_path("spec", base)
    $LOAD_PATH.unshift(spec_dir) unless $LOAD_PATH.include?(spec_dir)
    ::RSpec.reset
    status = ::RSpec::Core::Runner.run(
      ["--format", "progress", "--no-color", "--order", "defined", spec_file]
    )
    status.zero?
  end
end
