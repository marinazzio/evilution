# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/regexp_pattern"

# Rename a named regexp group: `/(?<user>\w+)@/` becomes `/(?<_user>\w+)@/`.
#
# The pattern still matches and still captures, but `m[:user]`, `$~[:user]` or
# the local variable that `/(?<user>...)/ =~ s` binds no longer find it. A survivor
# means nothing outside the pattern reads the named capture.
#
# References inside the pattern (`\k<user>`, `\g<user>`, `\k<user+1>`) are
# renamed along with the group, as is every group sharing the name, so the
# pattern itself stays valid and only outside references break; with every
# occurrence renamed together it always compiles. The new name is the old one
# with an underscore in front, more if that name is taken. As with
# RegexpCaptureToPassive, a regexp passed straight to `match?` or `!~` exposes
# no captures and is skipped.
class Evilution::Mutator::Operator::RegexpNamedGroupRename < Evilution::Mutator::Base
  CAPTURE_FREE_CALLS = %i[match? !~].freeze
  NAMED_GROUP_TOKENS = %i[named_ab named_sq].freeze

  # `(?<name>` / `(?'name'`, and `\k<name>`, `\g'name'`, `\k<name+1>`.
  GROUP_NAME = /\A(\(\?[<'])([^>']+)([>'])\z/
  REFERENCE_NAME = /\A(\\[kg][<'])([^>'+-]+)(.*)\z/m

  def initialize(**options)
    super
    @capture_free = Set.new.compare_by_identity
  end

  def visit_call_node(node)
    if CAPTURE_FREE_CALLS.include?(node.name)
      @capture_free << node.receiver
      @capture_free.merge(node.arguments.arguments) if node.arguments
    end
    super
  end

  def visit_regular_expression_node(node)
    pattern = Evilution::AST::RegexpPattern.parse(node) unless @capture_free.include?(node)
    rename_groups(node, pattern) if pattern
    super
  end

  private

  def rename_groups(node, pattern)
    occurrences = name_occurrences(pattern.tokens)
    group_names = occurrences.filter_map { |_token, name, kind| name if kind == :group }.uniq

    group_names.each do |name|
      renamed = free_name(name, group_names)
      edits = occurrences.select { |_token, other, _kind| other == name }
      emit_rename(node, edits, renamed)
    end
  end

  # Every group opener and named reference, with the name it carries.
  def name_occurrences(tokens)
    tokens.filter_map do |token|
      if token.type == :group && NAMED_GROUP_TOKENS.include?(token.token)
        [token, token.text[GROUP_NAME, 2], :group]
      elsif token.type == :backref && token.token.to_s.start_with?("name")
        [token, token.text[REFERENCE_NAME, 2], :reference]
      end
    end
  end

  def free_name(name, taken)
    candidate = "_#{name}"
    candidate = "_#{candidate}" while taken.include?(candidate)
    candidate
  end

  # The occurrences are spread through the pattern, while a mutation replaces
  # one contiguous range, so the range runs from the first to the last and is
  # rewritten with every occurrence renamed.
  def emit_rename(node, edits, renamed)
    start_offset = edits.first.first.start_offset
    length = edits.last.first.end_offset - start_offset

    add_mutation(
      offset: start_offset,
      length: length,
      replacement: apply_renames(byteslice_source(start_offset, length), edits, start_offset, renamed),
      node: node
    )
  end

  # Applied last to first, so a rename never shifts the offsets of those still
  # to come.
  def apply_renames(text, edits, base_offset, renamed)
    edits.reverse_each do |token, _name, kind|
      relative = token.start_offset - base_offset
      text = text.byteslice(0, relative) + renamed_text(token.text, kind, renamed) +
             text.byteslice((relative + token.text.bytesize)..)
    end
    text
  end

  def renamed_text(text, kind, renamed)
    pattern = kind == :group ? GROUP_NAME : REFERENCE_NAME
    text.sub(pattern) { "#{Regexp.last_match(1)}#{renamed}#{Regexp.last_match(3)}" }
  end
end
