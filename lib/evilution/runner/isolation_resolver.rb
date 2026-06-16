# frozen_string_literal: true

require_relative "../runner"
require_relative "../isolation/fork"
require_relative "../isolation/in_process"
require_relative "../rails_detector"
require_relative "../gem_detector"
require_relative "../integration/loading/test_load_path"

class Evilution::Runner::IsolationResolver
  PRELOAD_CANDIDATES = [
    File.join("spec", "rails_helper.rb"),
    File.join("spec", "spec_helper.rb"),
    File.join("test", "test_helper.rb")
  ].freeze
  # Conventional helpers for a non-Rails gem (no rails_helper). Ordered rspec
  # then minitest/test-unit; test/helper.rb covers the flat-layout convention
  # (rack, connection_pool, rake).
  GEM_PRELOAD_CANDIDATES = [
    File.join("spec", "spec_helper.rb"),
    File.join("test", "test_helper.rb"),
    File.join("test", "helper.rb")
  ].freeze

  def initialize(config, target_files:, hooks:)
    @config = config
    @target_files_callback = target_files
    @hooks = hooks
  end

  def isolator
    @isolator ||= build_isolator
  end

  def rails_root_detected?
    return @rails_root_detected if defined?(@rails_root_detected)

    @rails_root_detected = !detected_rails_root.nil?
  end

  def perform_preload
    return if config.preload == false
    return unless should_preload?

    path = resolve_preload_path
    return unless path

    prepare_load_path_for_preload(path)
    prepare_integration_for_preload
    require File.expand_path(path)
  rescue Evilution::ConfigError
    raise
  rescue ScriptError, StandardError => e
    raise Evilution::ConfigError.new(
      "failed to preload #{path.inspect}: #{e.class}: #{e.message}",
      file: path
    )
  end

  private

  attr_reader :config, :hooks

  # Under :fork, allow preloading — caller resolves whether a path exists (an
  # explicit --preload / preload: value, or an auto-detected rails_helper) and
  # bails early when none does. Under :in_process, only allow preloading when
  # the user explicitly asked via --preload or preload: in YAML — don't
  # auto-load spec/rails_helper.rb for a user who opted out of fork.
  def should_preload?
    return true if resolve_isolation == :fork

    config.preload.is_a?(String)
  end

  def target_files
    @target_files ||= @target_files_callback.call
  end

  def build_isolator
    case resolve_isolation
    when :fork then Evilution::Isolation::Fork.new(hooks: hooks)
    when :in_process then Evilution::Isolation::InProcess.new
    end
  end

  def resolve_isolation
    case config.isolation
    when :fork
      :fork
    when :in_process
      warn_in_process_under_rails if rails_root_detected?
      :in_process
    else # :auto
      fork_isolation_default? ? :fork : :in_process
    end
  end

  # Auto-isolation picks :fork for both Rails apps and packaged gems. A gem has
  # a spec/test suite whose helper (and the gem's own deps) must be preloaded in
  # the parent before forking; in_process can't preload without polluting the
  # host, so a plain non-Rails gem run with the in_process default scored 0.0
  # out-of-box (every mutation errored with 0 examples / NameError). Detecting
  # the gemspec and defaulting to :fork lets auto-preload fire.
  def fork_isolation_default?
    rails_root_detected? || gem_root_detected?
  end

  def gem_root_detected?
    !detected_gem_root.nil?
  end

  def detected_rails_root
    return @detected_rails_root if defined?(@detected_rails_root)

    @detected_rails_root = Evilution::RailsDetector.rails_root_for_any(target_files)
  end

  def detected_gem_root
    return @detected_gem_root if defined?(@detected_gem_root)

    @detected_gem_root = Evilution::GemDetector.gem_root_for_any(target_files)
  end

  # Preload files `require` a sibling helper relative to the test root, which
  # the suite's own runner satisfies via -Ispec/-Itest; evilution calls
  # Runner.run directly, so it must mirror that on $LOAD_PATH. The policy is
  # integration-specific so it does not over-widen the path:
  # - rspec: spec/rails_helper.rb / spec/spec_helper.rb need spec/ only (and
  #   rspec/core for RSpec.configure). Kept spec-only to match the RSpec
  #   FrameworkLoader and avoid prepending test/ ahead of spec/ in apps that
  #   have both (a bare `require "support/foo"` must still resolve from spec/).
  # - minitest/test-unit: a test/test_helper.rb doing a non-relative
  #   `require "support/..."` needs test/ on $LOAD_PATH. Route through
  #   TestLoadPath -- the same policy the per-mutation test load uses  -- so preload and mutation paths agree.
  def prepare_load_path_for_preload(preload_path)
    if config.integration == :rspec
      prepare_rspec_preload_load_path
    else
      prepare_test_preload_load_path(preload_path)
    end
  end

  def prepare_rspec_preload_load_path
    spec_dir = File.expand_path(resolve_spec_dir)
    $LOAD_PATH.unshift(spec_dir) unless $LOAD_PATH.include?(spec_dir)
    require "rspec/core"
  end

  def prepare_test_preload_load_path(preload_path)
    base = detected_rails_root || Evilution.project_base_dir
    Evilution::Integration::Loading::TestLoadPath.add!([preload_path], base: base)
  end

  def resolve_spec_dir
    root = detected_rails_root
    return File.join(root, "spec") if root

    "spec"
  end

  def resolve_preload_path
    return resolve_explicit_with_fallback(config.preload) if config.preload.is_a?(String)

    resolve_autodetected_preload
  end

  # Explicit preload path resolution with auto-detect fallthrough under :fork.
  # When the user-configured path is missing, surface a stderr warning naming
  # the missing path and try the auto-detect chain so a stale .evilution.yml
  # entry doesn't silently disable preloading. Fallthrough requires both
  # :fork isolation AND a detected Rails root (otherwise the chain has nowhere
  # to look and the explicit-missing error is raised directly).
  def resolve_explicit_with_fallback(explicit)
    return explicit if File.file?(explicit)

    raise_explicit_preload_missing(explicit) unless can_fallthrough_to_autodetect?

    warn_missing_explicit_preload(explicit)
    fallback = find_first_existing_candidate
    return fallback if fallback

    raise build_combined_missing_error(explicit)
  end

  def can_fallthrough_to_autodetect?
    resolve_isolation == :fork && !detected_rails_root.nil?
  end

  def resolve_autodetected_preload
    if detected_rails_root
      fallback = find_first_existing_candidate
      return fallback if fallback

      raise Evilution::ConfigError, autodetect_missing_message
    end

    resolve_autodetected_gem_preload
  end

  # For a non-Rails gem, prefer the conventional test helper (which loads the
  # gem's library AND the suite's framework/support setup) over the bare gem
  # entry, so example groups actually register. Fall back to the gem entry, and
  # flag a non-standard test layout so the user can pass --preload.
  def resolve_autodetected_gem_preload
    helper = find_first_existing_gem_helper
    return helper if helper

    entry = detected_gem_entry
    warn_unconventional_test_layout(entry) if detected_gem_root
    entry
  end

  def detected_gem_entry
    return @detected_gem_entry if defined?(@detected_gem_entry)

    root = detected_gem_root
    @detected_gem_entry = root && Evilution::GemDetector.gem_entry_for(root, target_paths: target_files)
  end

  def find_first_existing_candidate
    find_first_existing_under(detected_rails_root, PRELOAD_CANDIDATES)
  end

  def find_first_existing_gem_helper
    find_first_existing_under(detected_gem_root, GEM_PRELOAD_CANDIDATES)
  end

  def find_first_existing_under(root, candidates)
    return nil unless root

    candidates.each do |rel|
      abs = File.join(root, rel)
      return abs if File.file?(abs)
    end
    nil
  end

  def autodetect_missing_message
    "Preload file not found. Tried: [#{PRELOAD_CANDIDATES.join(", ")}]. " \
      "Pass --preload <file> or set preload: in .evilution.yml. " \
      "Use --no-preload (or preload: false) to disable preloading entirely."
  end

  def build_combined_missing_error(explicit)
    Evilution::ConfigError.new(
      "Preload file not found. Configured preload #{explicit.inspect} does not exist, " \
      "and none of the auto-detect candidates exist either. " \
      "Tried: [#{PRELOAD_CANDIDATES.join(", ")}]. " \
      "Pass --preload <file> or set preload: in .evilution.yml. " \
      "Use --no-preload (or preload: false) to disable preloading entirely.",
      file: explicit
    )
  end

  def raise_explicit_preload_missing(path)
    raise Evilution::ConfigError.new("preload file not found: #{path.inspect}", file: path)
  end

  # User preload files (spec_helper.rb, test_helper.rb) typically require
  # 'minitest/autorun', which installs an at_exit handler that re-parses ARGV
  # at process exit. The stub from Integration::Minitest#ensure_framework_loaded
  # only fires during baseline — too late to prevent the handler from being
  # registered. Stub before user code runs.
  def prepare_integration_for_preload
    return unless config.integration.to_s == "minitest"

    require "minitest"
    require_relative "../integration/minitest"
    Evilution::Integration::Minitest.stub_autorun!
  end

  def warn_missing_explicit_preload(path)
    return if config.quiet

    $stderr.write(
      "[evilution] warning: configured preload #{path.inspect} not found; " \
      "falling through to auto-detect chain.\n"
    )
  end

  # A gem was detected but none of the conventional test helpers exist, so the
  # suite likely uses a non-standard layout. Point at the expected locations and
  # the --preload escape hatch. The fallback wording reflects what will actually
  # happen: preload the gem entry when one was found, otherwise nothing is
  # preloaded (gem_entry can be nil when the gemspec name has no on-disk lib
  # entry) — without a helper, the gem entry alone may not register example
  # groups and mutations can error with 0 examples.
  def warn_unconventional_test_layout(gem_entry)
    return if config.quiet

    fallback =
      if gem_entry
        "Falling back to the gem entry (#{gem_entry})"
      else
        "No gem entry found to fall back to, so nothing will be preloaded"
      end

    $stderr.write(
      "[evilution] warning: no conventional test helper found under " \
      "#{detected_gem_root.inspect} (looked for #{GEM_PRELOAD_CANDIDATES.join(", ")}). " \
      "#{fallback}. If mutations error with '0 examples loaded' or NameError, " \
      "your test layout is non-standard — pass --preload <your helper>.\n"
    )
  end

  # When the user explicitly requests InProcess on a Rails project, warn once
  # per run. Rails wraps ActiveRecord transactions in
  # Thread.handle_interrupt(Exception => :never), which defers Timeout's
  # Thread#raise indefinitely — making InProcess unable to kill runaway mutants.
  def warn_in_process_under_rails
    return if config.quiet
    return if @warned_in_process_under_rails

    @warned_in_process_under_rails = true
    $stderr.write(
      "[evilution] warning: --isolation in_process is unsafe on Rails projects. " \
      "ActiveRecord wraps transactions in Thread.handle_interrupt(Exception => :never), " \
      "which swallows Timeout.timeout and can cause evilution to hang indefinitely on " \
      "mutants that introduce infinite loops. Use --isolation fork for reliable interruption.\n"
    )
  end
end
