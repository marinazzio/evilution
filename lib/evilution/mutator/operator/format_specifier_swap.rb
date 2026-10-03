# frozen_string_literal: true

require_relative "../operator"

# Loosen the conversion specifiers of a literal format string, one at a time:
#
#   format("%05d", n)    ->  format("%d", n)     flags and width dropped
#   sprintf("%.2f", x)   ->  sprintf("%f", x)    precision dropped
#                        ->  sprintf("%s", x)    rendered as a plain string
#
# A survivor means the output is produced but its shape — padding, decimals,
# number base — is never asserted.
#
# Reaches the format string of receiverless `format`, `sprintf` and `printf`
# and the string receiver of `"..." % args`, when it is a plain literal. Integer
# conversions (`%d`, `%i`, `%u`) are not turned into `%s`: for an integer
# argument both print the same digits.
class Evilution::Mutator::Operator::FormatSpecifierSwap < Evilution::Mutator::Base
  FORMAT_METHODS = %i[format sprintf printf].freeze

  # `%%` and `%{name}` are matched so they are not mistaken for the start of
  # a specifier; neither is mutated.
  SPECIFIER = /
    %(?:
      %
      | \{\w+\}
      | (?<name><\w+>)?(?<flags>[-+\ 0\#]*)(?<width>\d+|\*)?(?:\.(?<precision>\d+|\*))?(?<type>[a-zA-Z])
    )
  /x

  # Conversions whose output differs from `%s` for the values they take.
  STRINGIFIABLE_TYPES = %w[f e E g G a A x X o b B].freeze

  def visit_call_node(node)
    format_string = format_string_of(node)
    mutate_specifiers(node, format_string) if format_string
    super
  end

  private

  def format_string_of(node)
    candidate =
      if node.receiver.nil? && FORMAT_METHODS.include?(node.name)
        first_argument(node)
      elsif node.name == :%
        node.receiver
      end

    candidate if plain_literal?(candidate)
  end

  def first_argument(node)
    node.arguments.arguments.first if node.arguments
  end

  # A heredoc's content sits after the line that opens it, so edits inside
  # it are left alone along with interpolated strings. Only `%w[]` elements
  # lack an opening delimiter, and those never stand here on their own.
  def plain_literal?(node)
    node.is_a?(Prism::StringNode) && !node.opening_loc.slice.start_with?("<<")
  end

  def mutate_specifiers(node, format_string)
    specifiers(format_string).each do |match, offset|
      variants(match).each do |replacement|
        add_mutation(offset: offset, length: match[0].bytesize, replacement: replacement, node: node)
      end
    end
  end

  # Each conversion specifier with its offset in the file. The scan runs over
  # the source text between the quotes, so offsets line up with the file even
  # when the string holds escapes.
  def specifiers(format_string)
    content = format_string.content_loc
    text = byteslice_source(content.start_offset, content.length)

    text.to_enum(:scan, SPECIFIER).filter_map do
      match = Regexp.last_match
      [match, content.start_offset + match.byteoffset(0).first] unless match[:type].nil?
    end
  end

  # A `*` width or precision consumes an argument of its own, so dropping it
  # would shift every argument after it.
  def variants(match)
    return [] if [match[:width], match[:precision]].include?("*")

    name = match[:name]
    replacements = []
    replacements << "%#{name}#{match[:type]}" if modifiers?(match)
    replacements << "%#{name}s" if STRINGIFIABLE_TYPES.include?(match[:type])
    replacements
  end

  def modifiers?(match)
    !match[:flags].empty? || !match[:width].nil? || !match[:precision].nil?
  end
end
