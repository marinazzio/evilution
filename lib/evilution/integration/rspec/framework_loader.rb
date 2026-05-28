# frozen_string_literal: true

require_relative "../rspec"
require_relative "../crash_detector"

class Evilution::Integration::RSpec::FrameworkLoader
  def loaded?
    @loaded == true
  end

  def call
    return if @loaded

    require "rspec/core"
    add_spec_load_path
    Evilution::Integration::CrashDetector.register_with_rspec
    @loaded = true
  rescue LoadError => e
    raise Evilution::Error, "rspec-core is required but not available: #{e.message}"
  end

  private

  def add_spec_load_path
    # Anchor against PROJECT_ROOT inside an isolated worker (EV-wqxu /
    # GH #1278) so the project's spec/ dir lands on $LOAD_PATH — otherwise
    # `require "spec_helper"` resolves to a non-existent sandbox/spec and
    # every mutation errors as "loaded 0 examples".
    spec_dir = File.expand_path("spec", Evilution.project_base_dir)
    $LOAD_PATH.unshift(spec_dir) unless $LOAD_PATH.include?(spec_dir)
  end
end
