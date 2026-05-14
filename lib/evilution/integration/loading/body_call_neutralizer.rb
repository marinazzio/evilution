# frozen_string_literal: true

require "prism"
require_relative "../loading"

# Strip non-idempotent class/module-body side-effect calls from a mutated
# source before re-eval. Such calls (e.g. dry-monads `register_mixin`, plugin
# registries) raise on second invocation because they assume single-eval
# semantics. The first invocation already ran in the parent process during
# preload — the child fork inherits the resulting state, so re-running them
# is wasted work that aborts the eval before the mutated method takes effect.
#
# Strategy: walk Prism tree, find CallNodes that sit directly under a class
# or module body (not inside a def). Calls on a small allowlist of patterns
# known to be idempotent (`include`, `attr_*`, visibility modifiers, etc.)
# are preserved; everything else is replaced byte-for-byte with `nil`.
class Evilution::Integration::Loading::BodyCallNeutralizer
  IDEMPOTENT_CALLS = %i[
    include extend prepend using
    attr_reader attr_writer attr_accessor
    private public protected module_function private_class_method public_class_method
    alias_method
    define_method define_singleton_method
    delegate
    require require_relative autoload
  ].to_set.freeze

  class << self
    attr_writer :preloaded_features

    # Snapshot of `$LOADED_FEATURES` captured at parent preload-end (or lazily
    # initialised on first access). Forks inherit this set via copy-on-write,
    # so worker processes see the same membership the parent saw when it
    # finished its preload phase. Frozen so in-place mutation cannot silently
    # change neutralization semantics or force child forks to copy the page.
    def preloaded_features
      @preloaded_features ||= $LOADED_FEATURES.to_set.freeze
    end

    def reset_preload_snapshot!
      @preloaded_features = nil
    end
  end

  # `file_path` (optional) lets callers gate neutralization on whether the
  # target file was actually preloaded into the parent. The neutralizer's
  # premise — "this body has already run once, re-running it would double-
  # register" — only holds when the parent loaded the file. Lazy-loaded
  # plugin files (e.g. roda's `lib/roda/plugins/typecast_params.rb`, which
  # the gem only requires when the user opts in via `plugin :typecast_params`)
  # are first-loaded inside the child fork, so neutralizing their DSL calls
  # strips method definitions that subsequent sibling statements (alias, etc.)
  # depend on, producing cascading NameError. Callers that don't pass a path
  # get the legacy always-neutralize behavior.
  def call(source, file_path: nil)
    return source if file_path && !preloaded?(file_path)

    result = Prism.parse(source)
    return source if result.failure?

    edits = collect_edits(result.value)
    return source if edits.empty?

    apply_edits(source, edits)
  end

  private

  def preloaded?(file_path)
    self.class.preloaded_features.include?(File.expand_path(file_path))
  end

  def collect_edits(tree)
    edits = []
    walker = Walker.new(IDEMPOTENT_CALLS, edits)
    walker.visit(tree)
    edits
  end

  def apply_edits(source, edits)
    bytes = source.b
    edits.sort_by!(&:first).reverse_each do |start_offset, end_offset|
      bytes[start_offset, end_offset - start_offset] = "nil"
    end
    bytes.force_encoding(source.encoding)
  end

  class Walker < Prism::Visitor
    def initialize(allowlist, edits)
      super()
      @allowlist = allowlist
      @edits = edits
    end

    def visit_class_node(node)
      scan_body(node.body)
      super
    end

    def visit_module_node(node)
      scan_body(node.body)
      super
    end

    def visit_singleton_class_node(node)
      scan_body(node.body)
      super
    end

    private

    # Examine top-level statements in a class/module body. Only direct-child
    # CallNodes are candidates for neutralization. Calls nested inside any
    # other expression (constant assignments, conditionals, etc.) are left
    # alone — neutralizing them would break the surrounding expression.
    # Nested class/module bodies are walked through the normal visitor.
    def scan_body(body_node)
      return unless body_node.is_a?(Prism::StatementsNode)

      body_node.body.each do |stmt|
        next unless stmt.is_a?(Prism::CallNode)
        next if @allowlist.include?(stmt.name)
        next if stmt.receiver && !stmt.receiver.is_a?(Prism::SelfNode)

        @edits << [stmt.location.start_offset, replacement_end_offset(stmt)]
      end
    end

    # Prism CallNode location ends at the close of the call syntax (e.g. the
    # closing `)` or the `<<~MARKER` opener for a heredoc argument). It does
    # NOT include the heredoc body lines or the trailing terminator. Replacing
    # only the CallNode range leaves the heredoc body orphaned, producing a
    # parse error. Extend the range to cover any heredoc terminators inside
    # the call.
    def replacement_end_offset(call)
      collector = HeredocEndCollector.new
      collector.visit(call)
      [call.location.end_offset, *collector.end_offsets].max
    end
  end
  private_constant :Walker

  class HeredocEndCollector < Prism::Visitor
    attr_reader :end_offsets

    def initialize
      super
      @end_offsets = []
    end

    def visit_string_node(node)
      record_if_heredoc(node)
      super
    end

    def visit_interpolated_string_node(node)
      record_if_heredoc(node)
      super
    end

    def visit_interpolated_x_string_node(node)
      record_if_heredoc(node)
      super
    end

    def visit_x_string_node(node)
      record_if_heredoc(node)
      super
    end

    private

    def record_if_heredoc(node)
      return unless node.respond_to?(:heredoc?) && node.heredoc?

      closing = node.closing_loc
      return unless closing

      # Prism's heredoc closing_loc includes the leading whitespace and the
      # trailing newline of the terminator line (e.g. "    CODE\n"). Excluding
      # that newline preserves line structure so subsequent code lands on its
      # own line after the replacement.
      end_off = closing.end_offset
      slice = closing.slice
      end_off -= 1 if slice && slice.end_with?("\n")
      @end_offsets << end_off
    end
  end
  private_constant :HeredocEndCollector
end
