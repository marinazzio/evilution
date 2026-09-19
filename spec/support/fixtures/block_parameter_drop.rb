# frozen_string_literal: true

# Fixture for Mutator::Operator::BlockParameterDrop specs.
class BlockParameterDropTarget
  def single_param(users)
    users.each { |u| touch(u) }
  end

  def do_end(users)
    users.each do |u|
      touch(u)
    end
  end

  def destructured(pairs)
    pairs.each { |(key, value)| touch(key, value) }
  end

  def nested(users)
    users.each { |u| u.tags.each { |t| touch(t) } }
  end

  def referenced_in_nested_block(users)
    users.each { |u| u.tags.each { |t| touch(u, t) } }
  end

  def unused_param(users)
    users.each { |u| touch }
  end

  def underscore_param(users)
    users.each { |_u| touch }
  end

  def destructured_partial(pairs)
    pairs.each { |(key, value)| touch(key) }
  end

  def no_space_before_params(users)
    users.each {|u| touch(u) }
  end

  def empty_block(users)
    users.each { |u| }
  end

  def empty_pipes(users)
    users.each { || touch }
  end

  def underscore_referenced(users)
    users.each { |_u| touch(_u) }
  end

  def other_local_read(users)
    tmp = 1
    users.each { |u| touch(tmp) }
  end

  def local_in_nested_def(users)
    users.each do |u|
      def helper
        u = 1
        u
      end
    end
  end

  def nested_def_before_read(users)
    users.each do |u|
      def helper
        1
      end
      touch(u)
    end
  end

  def splat_param(users)
    users.each { |*rest| touch(rest) }
  end

  def keyword_param(users)
    users.each { |u, key: nil| touch(u, key) }
  end

  def keyword_rest_param(users)
    users.each { |u, **opts| touch(u, opts) }
  end

  def block_pass_param(users)
    users.each { |u, &blk| touch(u, blk) }
  end

  def two_params(pairs)
    pairs.each { |key, value| touch(key, value) }
  end

  def trailing_comma(pairs)
    pairs.each { |key,| touch(key) }
  end

  def block_locals(users)
    users.each do |u; tmp|
      tmp = u
      touch(tmp)
    end
  end

  def numbered_param(users)
    users.each { touch(_1) }
  end

  def no_params(users)
    users.each { touch }
  end

  def optional_param(users)
    users.map { |u, extra = nil| touch(u, extra) }
  end

  def lambda_literal
    ->(value) { touch(value) }
  end

  def touch(*args)
    args
  end
end
