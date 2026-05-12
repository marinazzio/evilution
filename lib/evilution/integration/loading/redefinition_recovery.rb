# frozen_string_literal: true

require_relative "../loading"
require_relative "../../ast/constant_names"

# Some DSLs (Rails 8 enum, define_method guards) raise ArgumentError on
# re-declaration. On such a conflict we strip constants declared in the source
# and retry the load once against a fresh namespace.
#
# A second class of idempotency violation comes from gem-internal registries
# (dry-monads `register_mixin`, Rails plugins, etc.) which raise when called
# a second time in the same process. For these we swallow the error: the
# class body executed up to the raise point — method defs preceding the
# registry call are already in place — and any state change blocked by the
# guard was intentional duplicate-prevention from the gem's side. Mutations
# that target a def *after* such a class-body call would not be applied;
# emit a one-shot warning so that mode is visible.
class Evilution::Integration::Loading::RedefinitionRecovery
  IDEMPOTENCY_PATTERNS = [
    "already registered",
    "already initialized",
    "already exists"
  ].freeze

  def initialize(constant_names: Evilution::AST::ConstantNames.new)
    @constant_names = constant_names
  end

  def call(source, &block)
    block.call
  rescue ArgumentError => e
    if redefinition_conflict?(e)
      remove_defined_constants(source)
      block.call
    elsif idempotency_violation?(e)
      warn_once_for(e)
      nil
    else
      raise
    end
  end

  private

  def redefinition_conflict?(error)
    error.message.include?("already defined")
  end

  def idempotency_violation?(error)
    msg = error.message
    IDEMPOTENCY_PATTERNS.any? { |pat| msg.include?(pat) }
  end

  def warn_once_for(error)
    return if @warned_messages&.include?(error.message)

    @warned_messages ||= []
    @warned_messages << error.message
    $stderr.write(
      "[evilution] swallowed idempotency violation on re-eval: " \
      "#{error.class}: #{error.message}. " \
      "Method defs preceding the raise point were re-applied; " \
      "mutations targeting code after the raise will not take effect.\n"
    )
  end

  def remove_defined_constants(source)
    @constant_names.call(source).reverse_each do |name|
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
end
