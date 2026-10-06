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
  # subclasses Module and undefines all of its instance methods, so asking it
  # anything lands in its method_missing and emits the deprecation; where the
  # deprecator's behaviour is :raise (grape's spec_helper sets that), the
  # sweep blows up on a module it merely walked past. So the module is never
  # asked: `Concern === mod` is answered by Concern, and the ivars are reached
  # through UnboundMethods, which bypass the object's own method table -- this
  # holds for any method_missing-based wrapper, not just ActiveSupport's.
  # EV-v2rc / GH #1581.
  #
  # `===` also leaves the module as it found it. Asking for its
  # singleton_class instead would create one for every module in the VM, each
  # of them a module the next sweep has to visit and give a singleton class
  # of its own; a long in-process run doubles its module count per mutation.
  IVAR_DEFINED = Object.instance_method(:instance_variable_defined?)
  IVAR_GET = Object.instance_method(:instance_variable_get)
  REMOVE_IVAR = Object.instance_method(:remove_instance_variable)
  private_constant :IVAR_DEFINED, :IVAR_GET, :REMOVE_IVAR

  def initialize(subpath_resolver: Evilution::LoadPath::SubpathResolver.new)
    @subpath_resolver = subpath_resolver
  end

  def call(file_path)
    return unless defined?(ActiveSupport::Concern)

    # Anchored on the project, not Dir.pwd: an isolated worker has chdir'd
    # into a per-mutation sandbox, where a relative path names nothing and no
    # concern would ever match.
    absolute = File.expand_path(file_path, Evilution.project_base_dir)
    subpath = @subpath_resolver.call(absolute)

    ObjectSpace.each_object(Module) do |mod|
      next unless ActiveSupport::Concern === mod # rubocop:disable Style/CaseEquality

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
