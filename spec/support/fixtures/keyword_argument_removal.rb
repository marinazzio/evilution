# frozen_string_literal: true

class KeywordArgumentRemovalTarget
  def two_keywords
    build(name: "x", size: 2)
  end

  def positional_and_keyword(value)
    build(value, name: "x")
  end

  def multiline
    build(
      name: "x",
      size: 2
    )
  end

  def with_double_splat(opts)
    build(name: "x", **opts)
  end

  def string_keys
    build("name" => "x", "size" => 2)
  end

  def shorthand(name, size)
    build(name:, size:)
  end

  def with_block_pass(block)
    build(name: "x", size: 2, &block)
  end

  def without_parens
    build name: "x", size: 2
  end

  def lone_keyword
    build(name: "x")
  end

  def hash_literal
    build({ name: "x", size: 2 })
  end
end
