# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/regexp_pattern"

# Drop the `i` or `m` option of a regexp literal: `/admin/i` becomes `/admin/`,
# `/a.b/m` becomes `/a.b/`.
#
# Without `i` the pattern matches only the letter case it is written in;
# without `m` a `.` no longer matches a newline. A survivor means no example
# feeds the pattern input in another case, or a newline where a `.` stands.
#
# A flag is only dropped where it changes something: `i` needs a cased letter
# written in the pattern (escapes such as `\d` and `\w` do not count), and `m`
# needs a `.` outside a character class. Other options (`x`, `o`, encodings)
# are left alone.
class Evilution::Mutator::Operator::RegexpOptionRemoval < Evilution::Mutator::Base
  def visit_regular_expression_node(node)
    pattern = Evilution::AST::RegexpPattern.parse(node)
    if pattern
      drop_option(node, "i") if node.ignore_case? && cased_letter?(pattern)
      drop_option(node, "m") if node.multi_line? && dot?(pattern)
    end

    super
  end

  private

  def cased_letter?(pattern)
    pattern.tokens.any? do |token|
      token.type == :literal && token.text.each_char.any? { |char| char.swapcase != char }
    end
  end

  def dot?(pattern)
    pattern.tokens.any? { |token| token.type == :meta && token.token == :dot }
  end

  # The options follow the closing delimiter: `/im`, `}mi`.
  def drop_option(node, option)
    closing = node.closing_loc

    add_mutation(
      offset: closing.start_offset + closing.slice.index(option),
      length: 1,
      replacement: "",
      node: node
    )
  end
end
