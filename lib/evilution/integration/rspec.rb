# frozen_string_literal: true

require "stringio"
require_relative "base"
require_relative "crash_detector"
require_relative "../spec_resolver"
require_relative "../related_spec_heuristic"

require_relative "../integration"

class Evilution::Integration::RSpec < Evilution::Integration::Base
  def initialize(test_files: nil, hooks: nil)
    @test_files = test_files
    @rspec_loaded = false
    @spec_resolver = Evilution::SpecResolver.new
    @related_spec_heuristic = Evilution::RelatedSpecHeuristic.new
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
    Evilution::Integration::CrashDetector.register_with_rspec
    @rspec_loaded = true
    fire_hook(:setup_integration_post, integration: :rspec)
  rescue LoadError => e
    raise Evilution::Error, "rspec-core is required but not available: #{e.message}"
  end

  def run_tests(mutation)
    reset_state

    out = StringIO.new
    err = StringIO.new
    command = "rspec"
    args = build_args(mutation)
    command = "rspec #{args.join(" ")}"

    detector = reset_crash_detector
    eg_before = snapshot_example_groups
    status = ::RSpec::Core::Runner.run(args, out, err)

    build_rspec_result(status, command, detector)
  rescue StandardError => e
    { passed: false, error: e.message, test_command: command }
  ensure
    release_rspec_state(eg_before)
  end

  def build_args(mutation)
    files = resolve_test_files(mutation)
    ["--format", "progress", "--no-color", "--order", "defined", *files]
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
      { passed: false, error: "test crashes: #{detector.crash_summary}", test_command: command }
    else
      { passed: false, test_command: command }
    end
  end

  def resolve_test_files(mutation)
    return test_files if test_files

    resolved = @spec_resolver.call(mutation.file_path)
    unless resolved
      warn_unresolved_spec(mutation.file_path)
      return ["spec"]
    end

    related = @related_spec_heuristic.call(mutation)
    ([resolved] + related).uniq
  end

  def warn_unresolved_spec(file_path)
    return if @warned_files.include?(file_path)

    @warned_files << file_path
    warn "[evilution] No matching spec found for #{file_path}, running full suite. " \
         "Use --spec to specify the spec file."
  end
end
