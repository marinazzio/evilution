# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::HashLiteral < Evilution::Mutator::Base
  RENAMED_KEY = "__evilution_mutated__"

  def visit_hash_node(node)
    if node.elements.any?
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "{}",
        node: node
      )

      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "nil",
        node: node
      )

      mutate_delete_pairs(node.elements)
      mutate_rename_keys(node.elements)
    end

    super
  end

  private

  # Delete each key/value pair in turn: a survivor means no example checks
  # that key. A single element is left to the `{}` replacement. A `**splat`
  # is not a pair and stays. So does a pair holding a heredoc: its body sits
  # after the closing brace, so one cut cannot take both, and the cut that
  # does not parse is dropped.
  def mutate_delete_pairs(elements)
    return if elements.one?

    elements.each_with_index do |element, index|
      delete_element(elements, index) if element.is_a?(Prism::AssocNode)
    end
  end

  # Rename each label key in turn (`a: 1`, `"a b": 1`): a survivor means no
  # example reads the value by that name. A key written with a rocket
  # (`:a => 1`, `"a" => 1`) is a literal of its own, and SymbolLiteral and
  # StringLiteral already replace it.
  def mutate_rename_keys(elements)
    elements.each do |element|
      rename_key(element) if element.is_a?(Prism::AssocNode) && label?(element.key)
    end
  end

  def label?(key)
    key.is_a?(Prism::SymbolNode) && !key.closing.nil? && key.closing.end_with?(":")
  end

  # A shorthand pair (`{ x: }`) reads its value from the key, so the value is
  # written out to stay what it was.
  def rename_key(pair)
    key = pair.key
    replacement = "#{RENAMED_KEY}:"
    replacement += " #{key.unescaped}" if pair.value.is_a?(Prism::ImplicitNode)

    add_mutation(
      offset: key.location.start_offset,
      length: key.location.length,
      replacement: replacement,
      node: key
    )
  end
end
