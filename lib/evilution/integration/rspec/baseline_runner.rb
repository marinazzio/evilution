# frozen_string_literal: true

require_relative "../rspec"

class Evilution::Integration::RSpec::BaselineRunner
  def call(spec_file)
    require "rspec/core"
    # Anchor against PROJECT_ROOT under EV-wqxu sandbox CWD; see
    # FrameworkLoader#add_spec_load_path for rationale.
    spec_dir = File.expand_path("spec", Evilution.project_base_dir)
    $LOAD_PATH.unshift(spec_dir) unless $LOAD_PATH.include?(spec_dir)
    ::RSpec.reset
    status = ::RSpec::Core::Runner.run(
      ["--format", "progress", "--no-color", "--order", "defined", spec_file]
    )
    status.zero?
  end
end
