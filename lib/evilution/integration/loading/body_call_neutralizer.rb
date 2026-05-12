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

  def call(source)
    result = Prism.parse(source)
    return source if result.failure?

    edits = collect_edits(result.value)
    return source if edits.empty?

    apply_edits(source, edits)
  end

  private

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

        @edits << [stmt.location.start_offset, stmt.location.end_offset]
      end
    end
  end
  private_constant :Walker
end
