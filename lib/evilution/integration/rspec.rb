# frozen_string_literal: true

require "fileutils"
require "stringio"
require "tmpdir"
require_relative "base"
require_relative "../spec_resolver"

require_relative "../integration"

class Evilution::Integration::RSpec < Evilution::Integration::Base
  def initialize(test_files: nil, hooks: nil)
    @test_files = test_files
    @rspec_loaded = false
    super(hooks: hooks)
  end

  def call(mutation)
    @original_content = nil
    @temp_dir = nil
    @lock_file = nil
    ensure_rspec_loaded
    @hooks.fire(:mutation_insert_pre, mutation: mutation, file_path: mutation.file_path) if @hooks
    apply_mutation(mutation)
    @hooks.fire(:mutation_insert_post, mutation: mutation, file_path: mutation.file_path) if @hooks
    run_rspec(mutation)
  ensure
    restore_original(mutation)
  end

  private

  attr_reader :test_files

  def ensure_rspec_loaded
    return if @rspec_loaded

    @hooks.fire(:setup_integration_pre, integration: :rspec) if @hooks
    require "rspec/core"
    @rspec_loaded = true
    @hooks.fire(:setup_integration_post, integration: :rspec) if @hooks
  rescue LoadError => e
    raise Evilution::Error, "rspec-core is required but not available: #{e.message}"
  end

  def apply_mutation(mutation)
    subpath = resolve_require_subpath(mutation.file_path)

    if subpath
      @temp_dir = Dir.mktmpdir("evilution")
      dest = File.join(@temp_dir, subpath)
      FileUtils.mkdir_p(File.dirname(dest))
      File.write(dest, mutation.mutated_source)
      $LOAD_PATH.unshift(@temp_dir)
    else
      # Fallback: direct write when file isn't under any $LOAD_PATH entry.
      # Acquire an exclusive lock to prevent concurrent workers from corrupting the file.
      lock_path = File.join(Dir.tmpdir, "evilution-#{File.expand_path(mutation.file_path).hash.abs}.lock")
      @lock_file = File.open(lock_path, File::CREAT | File::RDWR)
      @lock_file.flock(File::LOCK_EX)
      @original_content = File.read(mutation.file_path)
      File.write(mutation.file_path, mutation.mutated_source)
    end
  end

  def restore_original(mutation)
    if @temp_dir
      $LOAD_PATH.delete(@temp_dir)
      $LOADED_FEATURES.reject! { |f| f.start_with?(@temp_dir) }
      FileUtils.rm_rf(@temp_dir)
      @temp_dir = nil
    elsif @original_content
      File.write(mutation.file_path, @original_content)
      @lock_file&.flock(File::LOCK_UN)
      @lock_file&.close
      @lock_file = nil
    end
  end

  def resolve_require_subpath(file_path)
    absolute = File.expand_path(file_path)

    $LOAD_PATH.each do |entry|
      dir = File.expand_path(entry)
      prefix = dir.end_with?("/") ? dir : "#{dir}/"
      next unless absolute.start_with?(prefix)

      return absolute.delete_prefix(prefix)
    end

    nil
  end

  def run_rspec(mutation)
    # When used via the Runner with Isolation::Fork, each mutation is executed
    # in its own forked child process, so RSpec state (loaded example groups,
    # world, configuration) cannot accumulate across mutation runs — the child
    # process exits after each run.
    #
    # This integration can also be invoked directly (e.g. in specs or alternative
    # runners) without fork isolation. clear_examples reuses the existing World
    # and Configuration (avoiding per-run instance growth) while clearing loaded
    # example groups, constants, and configuration state.
    if ::RSpec.respond_to?(:clear_examples)
      ::RSpec.clear_examples
    else
      ::RSpec.reset
    end

    out = StringIO.new
    err = StringIO.new
    command = "rspec"
    args = build_args(mutation)
    command = "rspec #{args.join(" ")}"

    eg_before = snapshot_example_groups
    status = ::RSpec::Core::Runner.run(args, out, err)

    { passed: status.zero?, test_command: command }
  rescue StandardError => e
    { passed: false, error: e.message, test_command: command }
  ensure
    release_rspec_state(eg_before)
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
    # Remove ExampleGroups constants so the named reference is dropped.
    # We avoid a full RSpec.reset here because it creates new World and
    # Configuration instances each call; the pre-run reset already handles
    # that. Instead, clear the world's example_groups array (which holds
    # direct class references) and the source cache.
    ::RSpec::ExampleGroups.remove_all_constants if defined?(::RSpec::ExampleGroups)
    release_world_example_groups
  end

  def release_example_groups(eg_before)
    return unless eg_before

    ObjectSpace.each_object(Class) do |klass|
      next unless klass < ::RSpec::Core::ExampleGroup
      next if eg_before.include?(klass.object_id)

      # Remove nested module constants (LetDefinitions, NamedSubjectPreventSuper)
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

  def build_args(mutation)
    files = resolve_test_files(mutation)
    ["--format", "progress", "--no-color", "--order", "defined", *files]
  end

  def resolve_test_files(mutation)
    return test_files if test_files

    resolved = Evilution::SpecResolver.new.call(mutation.file_path)
    resolved ? [resolved] : ["spec"]
  end
end
