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
    i = 0
    while i < content.length
      if content[i] == "\\"
        i += 2
        next
      end

      if content[i] == "["
        i = skip_character_class(content, i)
        next
      end

      match = match_quantifier(content, i)
      if match
        add_mutation(
          offset: content_offset + i,
          length: match.length,
          replacement: "",
          node: node
        )
        i += match.length
      else
        i += 1
      end
    end
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
    i = 0
    while i < content.length
      if content[i] == "\\"
        anchor = match_backslash_anchor(content, i)
        if anchor
          add_mutation(
            offset: content_offset + i,
            length: anchor.length,
            replacement: "",
            node: node
          )
          i += anchor.length
        else
          i += 2
        end
        next
      end

      if content[i] == "["
        i = skip_character_class(content, i)
        next
      end

      if %w[^ $].include?(content[i])
        add_mutation(
          offset: content_offset + i,
          length: 1,
          replacement: "",
          node: node
        )
      end

      i += 1
    end
  end

  def match_backslash_anchor(content, pos)
    return nil unless content[pos] == "\\"

    two_char = content[pos, 2]
    return two_char if %w[\\A \\z \\Z].include?(two_char)

    nil
  end

  def remove_character_class_ranges(node, content, content_offset)
    i = 0
    while i < content.length
      if content[i] == "\\"
        i += 2
        next
      end

      if content[i] == "["
        scan_ranges_in_class(node, content, content_offset, i)
        i = skip_character_class(content, i)
      else
        i += 1
      end
    end
  end

  def scan_ranges_in_class(node, content, content_offset, class_start)
    i = skip_class_prefix(content, class_start)

    while i < content.length && content[i] != "]"
      if content[i] == "\\"
        i += 2
        next
      end

      emit_range_removal(node, content, content_offset, class_start, i) if content[i] == "-"
      i += 1
    end
  end

  def skip_class_prefix(content, class_start)
    i = class_start + 1
    i += 1 if i < content.length && content[i] == "^"
    i += 1 if i < content.length && content[i] == "]"
    i
  end

  def emit_range_removal(node, content, content_offset, class_start, pos)
    return unless pos > class_start + 1 && pos + 1 < content.length && content[pos + 1] != "]"

    add_mutation(
      offset: content_offset + pos,
      length: 1,
      replacement: "",
      node: node
    )
  end

  def skip_character_class(content, pos)
    i = pos + 1
    i += 1 if i < content.length && content[i] == "^"
    i += 1 if i < content.length && content[i] == "]"

    while i < content.length
      return i + 1 if content[i] == "]"

      i += content[i] == "\\" ? 2 : 1
    end

    i
  end
end
