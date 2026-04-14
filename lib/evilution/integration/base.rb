# frozen_string_literal: true

require "prism"
require_relative "../integration"

class Evilution::Integration::Base
  def self.baseline_runner
    raise NotImplementedError, "#{name}.baseline_runner must be implemented"
  end

  def self.baseline_options
    raise NotImplementedError, "#{name}.baseline_options must be implemented"
  end

  def initialize(hooks: nil)
    @hooks = hooks
  end

  def call(mutation)
    ensure_framework_loaded
    fire_hook(:mutation_insert_pre, mutation: mutation, file_path: mutation.file_path)
    load_error = apply_mutation(mutation)
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

  def apply_mutation(mutation)
    prism_error = validate_mutated_syntax(mutation.mutated_source)
    return prism_error if prism_error

    pin_autoloaded_constants(mutation.original_source)
    clear_concern_state(mutation.file_path)
    with_redefinition_recovery(mutation.original_source) do
      eval_mutated_source(mutation)
    end
    nil
  rescue SyntaxError => e
    {
      passed: false,
      error: "syntax error in mutated source: #{e.message}",
      error_class: e.class.name,
      error_backtrace: Array(e.backtrace).first(5)
    }
  rescue ScriptError, StandardError => e
    {
      passed: false,
      error: "#{e.class}: #{e.message}",
      error_class: e.class.name,
      error_backtrace: Array(e.backtrace).first(5)
    }
  end

  def validate_mutated_syntax(source)
    return nil if Prism.parse(source).success?

    {
      passed: false,
      error: "mutated source has syntax errors",
      error_class: "SyntaxError",
      error_backtrace: []
    }
  end

  # Evaluate the mutated source with __FILE__ set to the original path so
  # that `require_relative` and `__dir__` resolve against the real source
  # tree, where sibling files actually exist.
  def eval_mutated_source(mutation)
    absolute = File.expand_path(mutation.file_path)
    # rubocop:disable Security/Eval
    eval(mutation.mutated_source, TOPLEVEL_BINDING, absolute, 1)
    # rubocop:enable Security/Eval
  end

  def with_redefinition_recovery(original_source)
    yield
  rescue ArgumentError => e
    raise unless redefinition_conflict?(e)

    remove_defined_constants(original_source)
    yield
  end

  def redefinition_conflict?(error)
    error.message.include?("already defined")
  end

  def pin_autoloaded_constants(source)
    collect_constant_names(Prism.parse(source).value).each do |name|
      Object.const_get(name) if Object.const_defined?(name, false)
    rescue NameError # :nodoc:
      nil
    end
  end

  def collect_constant_names(node, nesting = [])
    names = []
    case node
    when Prism::ModuleNode, Prism::ClassNode
      const = node.constant_path.full_name
      qualified = nesting.any? && !const.include?("::") ? "#{nesting.join("::")}::#{const}" : const
      names << qualified
      names.concat(collect_constant_names(node.body, nesting + [const])) if node.body
    when Prism::ProgramNode
      names.concat(collect_constant_names(node.statements, nesting)) if node.statements
    when Prism::StatementsNode
      node.body.each { |child| names.concat(collect_constant_names(child, nesting)) }
    end
    names
  end

  def remove_defined_constants(source)
    collect_constant_names(Prism.parse(source).value).reverse_each do |name|
      parent_name, _, local_name = name.rpartition("::")
      parent = resolve_loaded_constant_parent(parent_name)
      next unless parent
      next unless parent.const_defined?(local_name, false)
      next if parent.autoload?(local_name)

      parent.send(:remove_const, local_name.to_sym)
    end
  end

  def resolve_loaded_constant_parent(parent_name)
    return Object if parent_name.empty?

    parent_name.split("::").reduce(Object) do |mod, part|
      return nil unless mod.const_defined?(part, false)
      return nil if mod.autoload?(part)

      resolved = mod.const_get(part, false)
      return nil unless resolved.is_a?(Module)

      resolved
    end
  end

  def clear_concern_state(file_path)
    return unless defined?(ActiveSupport::Concern)

    absolute = File.expand_path(file_path)
    subpath = resolve_require_subpath(file_path)

    ObjectSpace.each_object(Module) do |mod|
      next unless mod.singleton_class.ancestors.include?(ActiveSupport::Concern)

      %i[@_included_block @_prepended_block].each do |ivar|
        next unless mod.instance_variable_defined?(ivar)

        block = mod.instance_variable_get(ivar)
        block_file = block.source_location&.first
        next unless block_file

        expanded = File.expand_path(block_file)
        mod.remove_instance_variable(ivar) if source_matches?(expanded, absolute, subpath)
      end
    end
  end

  def source_matches?(block_path, absolute, subpath)
    block_path == absolute || (subpath && block_path.end_with?("/#{subpath}"))
  end

  def resolve_require_subpath(file_path)
    absolute = File.expand_path(file_path)
    best_subpath = nil

    $LOAD_PATH.each do |entry|
      dir = File.expand_path(entry)
      prefix = dir.end_with?("/") ? dir : "#{dir}/"
      next unless absolute.start_with?(prefix)

      candidate = absolute.delete_prefix(prefix)
      best_subpath = candidate if best_subpath.nil? || candidate.length < best_subpath.length
    end

    best_subpath
  end
end
