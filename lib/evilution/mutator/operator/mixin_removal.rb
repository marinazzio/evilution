# frozen_string_literal: true

require "prism"

require_relative "../operator"
require_relative "../../ast/class_body"

# Drop a mixin from a class or module body: `include`, `extend` and `prepend`
# calls are removed.
#
# The calls sit in the class body, outside every method, where no subject
# reaches them. They are attributed to the method anchoring the enclosing
# body (see Evilution::AST::ClassBody). A mixin call inside a method is left
# to the generic call operators.
class Evilution::Mutator::Operator::MixinRemoval < Evilution::Mutator::Base
  MIXIN_METHODS = %i[include extend prepend].freeze

  def call(subject, filter: nil)
    @subject = subject
    @file_source = File.read(subject.file_path)
    @mutations = []
    @filter = filter

    mixin_calls_for(subject).each { |call_node| emit_mixin_removal(call_node) }
    @mutations
  end

  private

  def mixin_calls_for(subject)
    tree = self.class.parsed_tree_for(subject.file_path, @file_source)

    Evilution::AST::ClassBody.anchored_at(tree, subject.line_number).flat_map do |body|
      body.declarations { |node| mixin_call?(node) }
    end
  end

  def mixin_call?(node)
    node.is_a?(Prism::CallNode) && MIXIN_METHODS.include?(node.name) && node.receiver.nil?
  end

  def emit_mixin_removal(call_node)
    add_mutation(
      offset: call_node.location.start_offset,
      length: call_node.location.length,
      replacement: "",
      node: call_node
    )
  end
end
