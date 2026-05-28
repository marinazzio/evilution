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
    # Anchor against PROJECT_ROOT so workers chdir'd into a per-mutation
    # sandbox (EV-wqxu / GH #1278) still register the project's spec/ dir
    # on $LOAD_PATH — without this `require "spec_helper"` from inside a
    # mutation spec resolves to a non-existent sandbox/spec and every
    # mutation errors as "loaded 0 examples".
    base = Evilution.in_isolated_worker? ? Evilution::PROJECT_ROOT : Dir.pwd
    spec_dir = File.expand_path("spec", base)
    $LOAD_PATH.unshift(spec_dir) unless $LOAD_PATH.include?(spec_dir)
  end
end
