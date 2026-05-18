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

  def no_params_outer
    def no_params_inner(&blk)
      blk.call
    end
  end

  def plain_params_outer(a)
    def plain_params_inner(&blk)
      blk.call
    end
  end

  def anon_forward_outer(input, &)
    def anon_forward_inner(&blk)
      blk.call
    end
    helper(map(input), &)
  end

  def block_param_outer(&outer_blk)
    def block_param_inner(&inner_blk)
      inner_blk.call
    end
    outer_blk.call
  end

  def optional_and_block(value = 1, &block)
    block.call(value)
  end

  def anon_block_empty_body(&)
  end
end
