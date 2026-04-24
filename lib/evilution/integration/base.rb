# frozen_string_literal: true

require_relative "../integration"
require_relative "loading/mutation_applier"

class Evilution::Integration::Base
  def self.baseline_runner
    raise NotImplementedError, "#{name}.baseline_runner must be implemented"
  end

  def self.baseline_options
    raise NotImplementedError, "#{name}.baseline_options must be implemented"
  end

  def initialize(hooks: nil, mutation_applier: Evilution::Integration::Loading::MutationApplier.new)
    @hooks = hooks
    @mutation_applier = mutation_applier
  end

  def call(mutation)
    ensure_framework_loaded
    fire_hook(:mutation_insert_pre, mutation: mutation, file_path: mutation.file_path)
    load_error = @mutation_applier.call(mutation)
    return load_error if load_error

    fire_hook(:mutation_insert_post, mutation: mutation, file_path: mutation.file_path)
    run_tests(mutation)
  end

  private

  def ensure_framework_loaded
    raise NotImplementedError, "#{self.class}#ensure_framework_loaded must be implemented"
  end

  def run_tests(_mutation)
    raise NotImplementedError, "#{self.class}#run_tests must be implemented"
  end

  def build_args(_mutation)
    raise NotImplementedError, "#{self.class}#build_args must be implemented"
  end

  def reset_state
    raise NotImplementedError, "#{self.class}#reset_state must be implemented"
  end

  def fire_hook(event, **payload)
    @hooks.fire(event, **payload) if @hooks
  end
end
