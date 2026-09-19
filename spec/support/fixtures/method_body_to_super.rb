# frozen_string_literal: true

# Fixture for Mutator::Operator::MethodBodyToSuper specs.
module MethodBodyToSuperHelper
  def helper_method(value)
    value
  end
end

class MethodBodyToSuperParent
  def inherited_method(value)
    value
  end
end

class MethodBodyToSuperChild < MethodBodyToSuperParent
  def plain_override(value)
    value * 2
  end

  def calls_super(value)
    super + 1
  end

  def calls_super_with_arguments(value)
    super(value.to_s) + 1
  end

  def empty_override(value); end

  def with_rescue(value)
    risky(value)
  rescue StandardError
    nil
  end

  def with_ensure(value)
    risky(value)
  ensure
    cleanup
  end

  def rescue_only
  rescue StandardError
    nil
  end

  def endless_override(value) = value + 1

  def self.singleton_override(value)
    value.to_s
  end

  private

  def risky(value)
    value
  end

  def cleanup
    nil
  end
end

class MethodBodyToSuperIncluder
  include MethodBodyToSuperHelper

  def mixed_in(value)
    value
  end
end

class MethodBodyToSuperPrepender
  prepend MethodBodyToSuperHelper

  def prepended_over(value)
    value
  end
end

class MethodBodyToSuperExtender
  extend MethodBodyToSuperHelper

  def self.singleton_with_extend(value)
    value
  end

  def instance_in_extender(value)
    value
  end
end

class MethodBodyToSuperPlain
  def no_parent(value)
    value
  end
end

module MethodBodyToSuperModule
  def module_method(value)
    value
  end
end

module MethodBodyToSuperIncludingModule
  include MethodBodyToSuperHelper

  def module_with_include(value)
    value
  end
end

class MethodBodyToSuperSingletonClass < MethodBodyToSuperParent
  class << self
    def in_singleton_class(value)
      value
    end
  end
end

class MethodBodyToSuperSingletonExtender
  extend MethodBodyToSuperHelper

  class << self
    def singleton_class_with_extend(value)
      value
    end
  end
end

class MethodBodyToSuperSingletonIncluder
  include MethodBodyToSuperHelper

  class << self
    def singleton_class_with_include(value)
      value
    end
  end
end
