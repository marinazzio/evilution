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

  def initialize(subpath_resolver: Evilution::LoadPath::SubpathResolver.new)
    @subpath_resolver = subpath_resolver
  end

  def call(file_path)
    return unless defined?(ActiveSupport::Concern)

    absolute = File.expand_path(file_path)
    subpath = @subpath_resolver.call(file_path)

    ObjectSpace.each_object(Module) do |mod|
      next unless mod.singleton_class.ancestors.include?(ActiveSupport::Concern)

      clear_concern_ivars(mod, absolute, subpath)
    end
  end

  private

  def clear_concern_ivars(mod, absolute, subpath)
    IVARS.each do |ivar|
      next unless mod.instance_variable_defined?(ivar)

      block = mod.instance_variable_get(ivar)
      block_file = block.source_location&.first
      next unless block_file

      expanded = File.expand_path(block_file)
      mod.remove_instance_variable(ivar) if source_matches?(expanded, absolute, subpath)
    end
  end

  def source_matches?(block_path, absolute, subpath)
    block_path == absolute || (subpath && block_path.end_with?("/#{subpath}"))
  end
end
