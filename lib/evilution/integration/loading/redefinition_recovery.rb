# frozen_string_literal: true

require_relative "../loading"
require_relative "../../ast/constant_names"

# Some DSLs (Rails 8 enum, define_method guards) raise ArgumentError on
# re-declaration. On such a conflict we strip constants declared in the source
# and retry the load once against a fresh namespace.
class Evilution::Integration::Loading::RedefinitionRecovery
  def initialize(constant_names: Evilution::AST::ConstantNames.new)
    @constant_names = constant_names
  end

  def call(source, &block)
    block.call
  rescue ArgumentError => e
    raise unless redefinition_conflict?(e)

    remove_defined_constants(source)
    block.call
  end

  private

  def redefinition_conflict?(error)
    error.message.include?("already defined")
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
