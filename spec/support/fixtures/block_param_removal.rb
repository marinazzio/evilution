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
end
