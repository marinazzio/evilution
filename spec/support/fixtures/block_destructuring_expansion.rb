# frozen_string_literal: true

# Fixture for Mutator::Operator::BlockDestructuringExpansion specs.
class BlockDestructuringExpansionTarget
  def group_then_sibling(pairs)
    pairs.each_with_index { |(key, value), index| touch(key, value, index) }
  end

  def sibling_then_group(pairs)
    pairs.each_with_index { |index, (key, value)| touch(index, key, value) }
  end

  def do_end_form(pairs)
    pairs.each_with_index do |(key, value), index|
      touch(key, value, index)
    end
  end

  def group_with_splat_sibling(pairs)
    pairs.each { |(key, value), *rest| touch(key, value, rest) }
  end

  def splat_inside_group(pairs)
    pairs.each { |(key, *rest), index| touch(key, rest, index) }
  end

  def nested_group(pairs)
    pairs.each { |((first, second), third), index| touch(first, second, third, index) }
  end

  def two_groups(pairs)
    pairs.each { |(first, second), (third, fourth)| touch(first, second, third, fourth) }
  end

  def group_with_block_param_sibling(pairs)
    pairs.each { |(key, value), &blk| touch(key, value, blk) }
  end

  def group_in_posts(pairs)
    pairs.each { |*rest, (key, value)| touch(rest, key, value) }
  end

  def every_parameter_kind(pairs)
    pairs.each { |(key, value), *rest, last, flag: 1, **opts, &blk| touch(key, value, rest, last, flag, opts, blk) }
  end

  def empty_pipes(pairs)
    pairs.each { || touch }
  end

  def lone_group(pairs)
    pairs.each { |(key, value)| touch(key, value) }
  end

  def lone_group_with_block_local(pairs)
    pairs.each do |(key, value); tmp|
      tmp = key
      touch(tmp, value)
    end
  end

  def flat_params(pairs)
    pairs.each { |key, value| touch(key, value) }
  end

  def no_params(pairs)
    pairs.each { touch }
  end

  def numbered_param(pairs)
    pairs.each { touch(_1) }
  end

  def lambda_with_group
    ->((key, value), index) { touch(key, value, index) }
  end

  def method_with_group((key, value), index)
    touch(key, value, index)
  end

  def touch(*args)
    args
  end
end
