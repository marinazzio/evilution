# frozen_string_literal: true

require "stringio"
require_relative "base"
require_relative "crash_detector"
require_relative "../spec_resolver"
require_relative "../spec_selector"
require_relative "../related_spec_heuristic"

require_relative "../integration"

class Evilution::Integration::RSpec < Evilution::Integration::Base
  def self.baseline_runner
    lambda { |spec_file|
      require "rspec/core"
      spec_dir = File.expand_path("spec")
      $LOAD_PATH.unshift(spec_dir) unless $LOAD_PATH.include?(spec_dir)
      ::RSpec.reset
      status = ::RSpec::Core::Runner.run(
        ["--format", "progress", "--no-color", "--order", "defined", spec_file]
      )
      status.zero?
    }
  end

  def self.baseline_options
    { runner: baseline_runner }
  end

  def initialize(test_files: nil, hooks: nil, related_specs_heuristic: false, fallback_to_full_suite: false,
                 spec_selector: nil)
    @test_files = test_files
    @rspec_loaded = false
    @spec_selector = spec_selector || Evilution::SpecSelector.new
    @related_spec_heuristic = Evilution::RelatedSpecHeuristic.new
    @related_specs_heuristic_enabled = related_specs_heuristic
    @fallback_to_full_suite = fallback_to_full_suite
    @crash_detector = nil
    @warned_files = Set.new
    super(hooks: hooks)
  end

  private

  attr_reader :test_files

  def ensure_framework_loaded
    return if @rspec_loaded

    fire_hook(:setup_integration_pre, integration: :rspec)
    require "rspec/core"
    add_spec_load_path
    Evilution::Integration::CrashDetector.register_with_rspec
    @rspec_loaded = true
    fire_hook(:setup_integration_post, integration: :rspec)
  rescue LoadError => e
    raise Evilution::Error, "rspec-core is required but not available: #{e.message}"
  end

  def run_tests(mutation)
    reset_state

    files = resolve_test_files(mutation)
    return unresolved_result(mutation) if files.nil?

    out = StringIO.new
    err = StringIO.new
    args = build_args(files)
    command = "rspec #{args.join(" ")}"

    detector = reset_crash_detector
    eg_before = snapshot_example_groups
    fe_before = snapshot_filtered_examples_keys
    rep_before = snapshot_reporter_lengths
    status = ::RSpec::Core::Runner.run(args, out, err)

    build_rspec_result(status, command, detector)
  rescue StandardError => e
    { passed: false, error: e.message, test_command: command }
  ensure
    release_rspec_state(eg_before)
    release_filtered_examples(fe_before)
    release_reporter_state(rep_before)
  end

  def build_args(files)
    ["--format", "progress", "--no-color", "--order", "defined", *files]
  end

  def unresolved_result(mutation)
    {
      passed: false,
      unresolved: true,
      error: "no matching spec resolved for #{mutation.file_path}",
      test_command: "rspec (skipped: no spec resolved for #{mutation.file_path})"
    }
  end

  def reset_state
    if ::RSpec.respond_to?(:clear_examples)
      ::RSpec.clear_examples
    else
      ::RSpec.reset
    end
  end

  def snapshot_example_groups
    groups = Set.new
    ObjectSpace.each_object(Class) do |klass|
      groups << klass.object_id if klass < ::RSpec::Core::ExampleGroup
    rescue TypeError # rubocop:disable Lint/SuppressedException
    end
    groups
  end

  def release_rspec_state(eg_before)
    release_example_groups(eg_before)
    ::RSpec::ExampleGroups.remove_all_constants if defined?(::RSpec::ExampleGroups)
    release_world_example_groups
  end

  def release_example_groups(eg_before)
    return unless eg_before

    ObjectSpace.each_object(Class) do |klass|
      next unless klass < ::RSpec::Core::ExampleGroup
      next if eg_before.include?(klass.object_id)

      klass.constants(false).each do |const|
        klass.send(:remove_const, const)
      rescue NameError # rubocop:disable Lint/SuppressedException
      end

      klass.instance_variables.each do |ivar|
        klass.remove_instance_variable(ivar)
      end
    rescue TypeError # rubocop:disable Lint/SuppressedException
    end
  end

  def release_world_example_groups
    world = ::RSpec.world
    world.instance_variable_get(:@example_groups).clear if world.instance_variable_defined?(:@example_groups)
    world.instance_variable_set(:@sources_by_path, {}) if world.instance_variable_defined?(:@sources_by_path)
  end

  def snapshot_filtered_examples_keys
    fe = rspec_world_ivar(:@filtered_examples)
    fe ? Set.new(fe.keys.map(&:object_id)) : nil
  end

  def snapshot_reporter_lengths
    reporter = rspec_config_ivar(:@reporter)
    return nil unless reporter

    %i[@examples @failed_examples @pending_examples].each_with_object({}) do |ivar, acc|
      next unless reporter.instance_variable_defined?(ivar)

      arr = reporter.instance_variable_get(ivar)
      acc[ivar] = arr.length if arr.is_a?(Array)
    end
  end

  def release_filtered_examples(snapshot_keys)
    fe = rspec_world_ivar(:@filtered_examples)
    return unless fe && snapshot_keys

    fe.each_key.to_a.each do |k|
      fe.delete(k) unless snapshot_keys.include?(k.object_id)
    end
  end

  def release_reporter_state(lengths)
    return unless lengths

    reporter = rspec_config_ivar(:@reporter)
    return unless reporter

    lengths.each do |ivar, length|
      arr = reporter.instance_variable_get(ivar)
      arr.slice!(length..) if arr.is_a?(Array) && arr.length > length
    end
  end

  def rspec_world_ivar(ivar)
    world = ::RSpec.world
    world.instance_variable_defined?(ivar) ? world.instance_variable_get(ivar) : nil
  end

  def rspec_config_ivar(ivar)
    config = ::RSpec.configuration
    config.instance_variable_defined?(ivar) ? config.instance_variable_get(ivar) : nil
  end

  def reset_crash_detector
    if @crash_detector
      @crash_detector.reset
    else
      @crash_detector = Evilution::Integration::CrashDetector.new(StringIO.new)
      ::RSpec.configuration.add_formatter(@crash_detector)
    end
    @crash_detector
  end

  def build_rspec_result(status, command, detector)
    if status.zero?
      { passed: true, test_command: command }
    elsif detector.only_crashes?
      {
        passed: false,
        test_crashed: true,
        error: "test crashes: #{detector.crash_summary}",
        test_command: command
      }
    else
      { passed: false, test_command: command }
    end
  end

  def resolve_test_files(mutation)
    return test_files if test_files

    resolved = Array(@spec_selector.call(mutation.file_path))
    if resolved.empty?
      warn_unresolved_spec(mutation.file_path)
      return @fallback_to_full_suite ? ["spec"] : nil
    end

    return resolved unless @related_specs_heuristic_enabled

    related = @related_spec_heuristic.call(mutation)
    (resolved + related).uniq
  end

  def warn_unresolved_spec(file_path)
    return if @warned_files.include?(file_path)

    @warned_files << file_path
    action = @fallback_to_full_suite ? "running full suite" : "marking mutation unresolved"
    warn "[evilution] No matching spec found for #{file_path}, #{action}. " \
         "Use --spec to specify the spec file."
  end

  # RSpec's CLI adds spec/ to $LOAD_PATH so that `--require spec_helper`
  # (commonly in .rspec) resolves. We call Runner.run directly, bypassing
  # the CLI, so we must replicate this.
  def add_spec_load_path
    spec_dir = File.expand_path("spec")
    $LOAD_PATH.unshift(spec_dir) unless $LOAD_PATH.include?(spec_dir)
  end
end
