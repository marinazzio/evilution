# frozen_string_literal: true

require_relative "../loading"
require_relative "../../load_path/subpath_resolver"

# Re-evaluating an `ActiveSupport::Concern` module raises
# "MultipleIncludedBlocks" because AS::Concern records the block source
# location on the first include/prepend call. Before a re-eval we clear the
# `@_included_block` / `@_prepended_block` ivar on modules whose block came
# from the file we're about to re-eval.
class Evilution::Integration::Loading::ConcernStateCleaner
  IVARS = %i[@_included_block @_prepended_block].freeze

  # ObjectSpace hands us every Module in the VM, including ones that answer no
  # message honestly. ActiveSupport::Deprecation::DeprecatedConstantProxy
  # subclasses Module and undefines all of its instance methods, so a plain
  # `mod.singleton_class` lands in its method_missing and emits the
  # deprecation; where the deprecator's behaviour is :raise (grape's
  # spec_helper sets that), the sweep blows up on a module it merely walked
  # past. Calling through UnboundMethods bypasses the object's own method
  # table, so a proxy is never given the chance to intercept -- and this holds
  # for any method_missing-based wrapper, not just ActiveSupport's.
  # EV-v2rc / GH #1581.
  SINGLETON_CLASS = Object.instance_method(:singleton_class)
  IVAR_DEFINED = Object.instance_method(:instance_variable_defined?)
  IVAR_GET = Object.instance_method(:instance_variable_get)
  REMOVE_IVAR = Object.instance_method(:remove_instance_variable)
  private_constant :SINGLETON_CLASS, :IVAR_DEFINED, :IVAR_GET, :REMOVE_IVAR

  def initialize(subpath_resolver: Evilution::LoadPath::SubpathResolver.new)
    @subpath_resolver = subpath_resolver
  end

  def call(file_path)
    return unless defined?(ActiveSupport::Concern)

    absolute = File.expand_path(file_path)
    subpath = @subpath_resolver.call(file_path)

    ObjectSpace.each_object(Module) do |mod|
      next unless SINGLETON_CLASS.bind_call(mod).ancestors.include?(ActiveSupport::Concern)

      clear_concern_ivars(mod, absolute, subpath)
    end
  end

  private

  def clear_concern_ivars(mod, absolute, subpath)
    IVARS.each do |ivar|
      next unless IVAR_DEFINED.bind_call(mod, ivar)

      block = IVAR_GET.bind_call(mod, ivar)
      block_file = block.source_location&.first
      next unless block_file

      expanded = File.expand_path(block_file)
      REMOVE_IVAR.bind_call(mod, ivar) if source_matches?(expanded, absolute, subpath)
    end
  end

  def source_matches?(block_path, absolute, subpath)
    block_path == absolute || (subpath && block_path.end_with?("/#{subpath}"))
  end
end
