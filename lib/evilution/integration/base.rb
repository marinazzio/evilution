# frozen_string_literal: true

require "fileutils"
require "prism"
require "tmpdir"
require_relative "../integration"
require_relative "../temp_dir_tracker"

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
    @temp_dir = nil
    ensure_framework_loaded
    fire_hook(:mutation_insert_pre, mutation: mutation, file_path: mutation.file_path)
    load_error = apply_mutation(mutation)
    return load_error if load_error

    fire_hook(:mutation_insert_post, mutation: mutation, file_path: mutation.file_path)
    run_tests(mutation)
  ensure
    restore_original(mutation)
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
    @temp_dir = Dir.mktmpdir("evilution")
    Evilution::TempDirTracker.register(@temp_dir)
    @displaced_feature = nil
    subpath = resolve_require_subpath(mutation.file_path)

    if subpath
      apply_via_require(mutation, subpath)
    else
      apply_via_load(mutation)
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

  def apply_via_require(mutation, subpath)
    dest = File.join(@temp_dir, subpath)
    FileUtils.mkdir_p(File.dirname(dest))
    File.write(dest, mutation.mutated_source)
    $LOAD_PATH.unshift(@temp_dir)
    displace_loaded_feature(mutation.file_path)
    pin_autoloaded_constants(mutation.original_source)
    clear_concern_state(mutation.file_path)
    require(subpath.delete_suffix(".rb"))
  end

  def apply_via_load(mutation)
    absolute = File.expand_path(mutation.file_path)
    dest = File.join(@temp_dir, absolute)
    FileUtils.mkdir_p(File.dirname(dest))
    File.write(dest, mutation.mutated_source)
    pin_autoloaded_constants(mutation.original_source)
    clear_concern_state(mutation.file_path)
    load(dest)
  end

  def restore_original(_mutation)
    return unless @temp_dir

    $LOAD_PATH.delete(@temp_dir)
    $LOADED_FEATURES.reject! { |f| f.start_with?(@temp_dir) }
    $LOADED_FEATURES << @displaced_feature if @displaced_feature && !$LOADED_FEATURES.include?(@displaced_feature)
    @displaced_feature = nil
    FileUtils.rm_rf(@temp_dir)
    Evilution::TempDirTracker.unregister(@temp_dir)
    @temp_dir = nil
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

  def displace_loaded_feature(file_path)
    absolute = File.expand_path(file_path)
    return unless $LOADED_FEATURES.include?(absolute)

    @displaced_feature = absolute
    $LOADED_FEATURES.delete(absolute)
  end
end
