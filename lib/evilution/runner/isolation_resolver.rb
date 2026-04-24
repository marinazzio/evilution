# frozen_string_literal: true

require_relative "../isolation/fork"
require_relative "../isolation/in_process"
require_relative "../rails_detector"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass

class Evilution::Runner::IsolationResolver
  PRELOAD_CANDIDATES = [
    File.join("spec", "rails_helper.rb"),
    File.join("test", "test_helper.rb")
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

    path = resolve_preload_path
    return unless path
    return unless should_preload?

    prepare_load_path_for_preload
    require File.expand_path(path)
  rescue ScriptError, StandardError => e
    raise Evilution::ConfigError.new(
      "failed to preload #{path.inspect}: #{e.class}: #{e.message}",
      file: path
    )
  end

  private

  attr_reader :config, :hooks

  # Preload runs under :fork always (Rails autodetect path). Under :in_process,
  # only run when the user explicitly asked via --preload or preload: in YAML —
  # don't auto-load spec/rails_helper.rb for a user who opted out of fork.
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
      rails_root_detected? ? :fork : :in_process
    end
  end

  def detected_rails_root
    return @detected_rails_root if defined?(@detected_rails_root)

    @detected_rails_root = Evilution::RailsDetector.rails_root_for_any(target_files)
  end

  # Preload files (e.g. spec/rails_helper.rb) typically `require 'spec_helper'`
  # which needs spec/ on $LOAD_PATH, and use `RSpec.configure` which needs
  # rspec/core loaded. The RSpec CLI normally sets this up, but evilution
  # calls Runner.run directly.
  def prepare_load_path_for_preload
    spec_dir = File.expand_path(resolve_spec_dir)
    $LOAD_PATH.unshift(spec_dir) unless $LOAD_PATH.include?(spec_dir)
    require "rspec/core" if config.integration == :rspec
  end

  def resolve_spec_dir
    root = detected_rails_root
    return File.join(root, "spec") if root

    "spec"
  end

  def resolve_preload_path
    if config.preload.is_a?(String)
      unless File.file?(config.preload)
        raise Evilution::ConfigError.new(
          "preload file not found: #{config.preload.inspect}",
          file: config.preload
        )
      end
      return config.preload
    end

    root = detected_rails_root
    return nil unless root

    PRELOAD_CANDIDATES.each do |rel|
      abs = File.join(root, rel)
      return abs if File.file?(abs)
    end
    nil
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
