# frozen_string_literal: true

# Fixture for Mutator::Operator::ForwardingSuperToExplicit specs.
class ForwardingSuperToExplicitTarget < Object
  def positional(value)
    super
  end

  def optional(value = 1)
    super
  end

  def keyword(key: 1)
    super
  end

  def splat(*args)
    super
  end

  def forwarding(...)
    super
  end

  def with_block_argument(value)
    super { 1 }
  end

  def inside_a_block(value)
    [1, 2].each { super }
  end

  def among_statements(value)
    prepare
    super
  end

  def endless_super(value) = super

  def self.singleton(value)
    super
  end

  def post_required(*rest, last)
    super
  end

  def super_after_inner_def(value)
    def paramless_helper
      1
    end
    super
  end

  def super_inside_super_block(value)
    super { super }
  end

  def block_only(&blk)
    super
  end

  def no_parameters
    super
  end

  def explicit_super(value)
    super(value)
  end

  def no_super(value)
    value
  end

  def outer_with_inner(value)
    def inner(other)
      super
    end
  end

  def outer_with_paramless_inner(value)
    def paramless_inner
      super
    end
  end

  def prepare
    nil
  end
end
