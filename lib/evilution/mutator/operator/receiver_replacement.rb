# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ReceiverReplacement < Evilution::Mutator::Base
  # Ruby reserved words. A call like `self.class` — when stripped of its
  # `self.` receiver — becomes the bare token `class`, which the parser reads
  # as the class-definition keyword rather than a method call. Producing this
  # mutation guarantees an unparseable result. Skip when the call's method
  # name collides with any reserved keyword.
  RUBY_RESERVED_KEYWORDS = %i[
    BEGIN END __ENCODING__ __FILE__ __LINE__
    alias and begin break case class def defined? do else elsif end
    ensure false for if in module next nil not or redo rescue retry
    return self super then true undef unless until when while yield
  ].to_set.freeze

  def visit_call_node(node)
    if eligible_self_call?(node)
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: call_without_self_text(node),
        node: node
      )
    end

    super
  end

  private

  def eligible_self_call?(node)
    return false unless node.receiver.is_a?(Prism::SelfNode)
    return false if reserved_keyword_method?(node.name)

    true
  end

  # `self.class = value` is a writer call whose Prism `name` is `:class=` —
  # not `:class` — so a literal lookup in RUBY_RESERVED_KEYWORDS misses it,
  # and stripping the receiver leaves `class = value` (parse error). Normalize
  # the trailing `=` from writer forms before comparing.
  def reserved_keyword_method?(name)
    base = name.to_s.chomp("=").to_sym
    RUBY_RESERVED_KEYWORDS.include?(base)
  end

  def call_without_self_text(node)
    message_start = node.message_loc.start_offset
    call_end = node.location.start_offset + node.location.length
    @file_source.byteslice(message_start, call_end - message_start)
  end
end
