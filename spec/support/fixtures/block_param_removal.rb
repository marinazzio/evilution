# frozen_string_literal: true

class BlockParamRemovalExample
  def only_block_param(&block)
    block.call
  end

  def with_other_params(a, b, &block)
    block.call(a, b)
  end

  def with_keyword_and_block(name:, &block)
    block.call(name)
  end

  def no_block_param(a, b)
    a + b
  end

  def no_params
    42
  end

  def anon_block_forwarded(input, &)
    helper(map(input), &)
  end

  def anon_block_unused(input, &)
    input * 2
  end

  def named_block_referenced(input, &block)
    helper(input, &block)
  end

  def anon_block_with_nested_def(input, &)
    # Nested def has its own `&` param; the orphan `&` belongs to `inner`,
    # not the outer. Removing the outer `&` is safe.
    def inner(x, &)
      helper(x, &)
    end
    inner(input)
  end
end
