# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::RegexSimplification < Evilution::Mutator::Base
  def visit_regular_expression_node(node)
    content = node.content
    return super if content.empty?

    content_offset = node.content_loc.start_offset

    remove_quantifiers(node, content, content_offset)
    remove_anchors(node, content, content_offset)
    remove_character_class_ranges(node, content, content_offset)

    super
  end

  private

  def remove_quantifiers(node, content, content_offset)
    scan_regex_positions(content) do |kind, i|
      case kind
      when :backslash then 2
      when :class_open then class_skip(content, i)
      when :char then emit_quantifier_at(node, content, content_offset, i)
      end
    end
  end

  def emit_quantifier_at(node, content, content_offset, i)
    match = match_quantifier(content, i)
    return 1 if match.nil?

    add_mutation(offset: content_offset + i, length: match.length, replacement: "", node: node)
    match.length
  end

  def match_quantifier(content, pos)
    case content[pos]
    when "+", "*", "?"
      content[pos]
    when "{"
      if (m = content[pos..].match(/\A\{\d+(?:,\d*)?\}/))
        m[0]
      end
    end
  end

  def remove_anchors(node, content, content_offset)
    scan_regex_positions(content) do |kind, i|
      case kind
      when :backslash then try_emit_backslash_anchor(node, content, content_offset, i)
      when :class_open then class_skip(content, i)
      when :char
        try_emit_caret_dollar(node, content, content_offset, i)
        1
      end
    end
  end

  def try_emit_backslash_anchor(node, content, content_offset, i)
    anchor = match_backslash_anchor(content, i)
    return 2 if anchor.nil?

    add_mutation(offset: content_offset + i, length: anchor.length, replacement: "", node: node)
    anchor.length
  end

  def try_emit_caret_dollar(node, content, content_offset, i)
    return unless %w[^ $].include?(content[i])

    add_mutation(offset: content_offset + i, length: 1, replacement: "", node: node)
  end

  def match_backslash_anchor(content, pos)
    return nil unless content[pos] == "\\"

    two_char = content[pos, 2]
    return two_char if %w[\\A \\z \\Z].include?(two_char)

    nil
  end

  def remove_character_class_ranges(node, content, content_offset)
    scan_regex_positions(content) do |kind, i|
      case kind
      when :backslash then 2
      when :class_open
        scan_ranges_in_class(node, content, content_offset, i)
        class_skip(content, i)
      when :char then 1
      end
    end
  end

  def scan_ranges_in_class(node, content, content_offset, class_start)
    first_item = skip_class_prefix(content, class_start)
    i = first_item

    while i < content.length && content[i] != "]"
      if content[i] == "\\"
        i += 2
        next
      end

      emit_range_removal(node, content, content_offset, first_item, i) if content[i] == "-"
      i += 1
    end
  end

  def skip_class_prefix(content, class_start)
    i = class_start + 1
    i += 1 if i < content.length && content[i] == "^"
    i += 1 if i < content.length && content[i] == "]"
    i
  end

  def emit_range_removal(node, content, content_offset, first_item, pos)
    return unless pos > first_item && pos + 1 < content.length && content[pos + 1] != "]"

    add_mutation(
      offset: content_offset + pos,
      length: 1,
      replacement: "",
      node: node
    )
  end

  # Walks `content` yielding (kind, position) for each significant token:
  # :backslash for an escape sequence, :class_open for `[`, :char for any
  # other byte. The block returns the number of characters to advance from
  # `position` — callers decide how to handle each case (skip, emit a
  # mutation, descend into a character class, etc.).
  def scan_regex_positions(content)
    i = 0
    while i < content.length
      advance = case content[i]
                when "\\" then yield(:backslash, i)
                when "[" then yield(:class_open, i)
                else yield(:char, i)
                end
      i += advance
    end
  end

  def class_skip(content, pos)
    skip_character_class(content, pos) - pos
  end

  def skip_character_class(content, pos)
    scan_to_class_close(content, skip_class_prefix(content, pos))
  end

  def scan_to_class_close(content, start)
    i = start
    while i < content.length
      return i + 1 if content[i] == "]"

      i += content[i] == "\\" ? 2 : 1
    end
    i
  end
end
