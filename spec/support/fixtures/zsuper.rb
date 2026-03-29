# frozen_string_literal: true

class ZsuperExample
  def greet # rubocop:disable Lint/UselessMethodDefinition
    super
  end

  def work(a, b) # rubocop:disable Lint/UselessMethodDefinition
    super
  end

  def no_super
    "plain"
  end
end
