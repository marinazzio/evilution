# frozen_string_literal: true

# Reads of `recv[key]` in and around a guard on the same read. The spec lists,
# per method, which of them `index_to_fetch` can turn into `fetch` without
# changing behavior.
class GuardedIndexFetchFixture
  def unguarded(config)
    config[:k]
  end

  def if_guard(config)
    if config[:k]
      "size: #{config[:k]}"
    end
  end

  def modifier_if(config, style)
    style << config[:k] if config[:k]
  end

  def modifier_unless(config, style)
    style << config[:k] unless config[:k]
  end

  def ternary(config)
    config[:k] ? config[:k] : 1
  end

  def ternary_else(config)
    config[:k] ? 1 : config[:k]
  end

  def else_branch(config)
    if config[:k]
      1
    else
      config[:k]
    end
  end

  def unless_else(config)
    unless config[:k]
      config[:k]
    else
      config[:k]
    end
  end

  def elsif_guard(config, other)
    if other
      config[:k]
    elsif config[:k]
      config[:k]
    else
      config[:k]
    end
  end

  def and_guard(config)
    config[:k] && config[:k].size
  end

  def and_keyword(config)
    config[:k] and config[:k].size
  end

  def and_chain(config, enabled)
    enabled && config[:k] && config[:k].size
  end

  def or_guard(config)
    config[:k] || config[:k]
  end

  def conjunct_guard(config, enabled)
    if enabled && config[:k]
      config[:k]
    end
  end

  def parenthesized_guard(config, enabled)
    if (enabled && (config[:k]))
      config[:k]
    end
  end

  def left_conjunct_guard(config, enabled)
    if config[:k] && enabled
      config[:k]
    end
  end

  def unrelated_conjuncts(config, enabled, other)
    if enabled && other
      config[:k]
    end
  end

  def parenthesized_sequence_guard(config, enabled)
    if (enabled; config[:k])
      config[:k]
    end
  end

  def parenthesized_unrelated_guard(config, enabled)
    if (enabled)
      config[:k]
    end
  end

  def disjunct_guard(config, enabled)
    if enabled || config[:k]
      config[:k]
    end
  end

  def negated_guard(config)
    if !config[:k]
      config[:k]
    end
  end

  def while_guard(config)
    while config[:k]
      config[:k]
    end
  end

  def nested_ifs(config, other)
    if config[:k]
      if other
        config[:k]
      end
    end
  end

  def different_key(config)
    if config[:a]
      config[:b]
    end
  end

  def different_receiver(config, other)
    if config[:k]
      other[:k]
    end
  end

  def symbol_and_string_key(config)
    if config[:k]
      config["k"]
    end
  end

  def string_key(row)
    if row["name"]
      row["name"]
    end
  end

  def integer_key(list)
    if list[0]
      list[0]
    end
  end

  def dynamic_key(config, key)
    if config[key]
      config[key]
    end
  end

  def key_predicate(config)
    config[:k] if config.key?(:k)
  end

  def has_key_predicate(config)
    config[:k] if config.has_key?(:k)
  end

  def include_predicate(config)
    config[:k] if config.include?(:k)
  end

  def member_predicate(config)
    config[:k] if config.member?(:k)
  end

  def key_predicate_other_key(config)
    config[:k] if config.key?(:other)
  end

  def key_predicate_other_receiver(config, other)
    config[:k] if other.key?(:k)
  end

  def unrelated_call_with_key(config)
    config[:k] if config.eql?(:k)
  end

  def present_on_other_read(config)
    config[:k] if config[:other].present?
  end

  def unrelated_predicate(config)
    config[:k] if config.frozen?
  end

  def present_guard(config)
    if config[:k].present?
      config[:k]
    end
  end

  def blank_guard(config)
    if config[:k].blank?
      config[:k]
    end
  end

  def dig_guard(config)
    config[:k] if config.dig(:k)
  end

  def deep_dig_guard(config)
    config[:k] if config.dig(:a, :k)
  end

  def ivar_receiver
    if @config[:k]
      @config[:k]
    end
  end

  def constant_receiver
    if ENV["HOME"]
      ENV["HOME"]
    end
  end

  def method_receiver
    if settings[:k]
      settings[:k]
    end
  end

  def chained_receiver(user)
    if user.settings[:k]
      user.settings[:k]
    end
  end

  def self_receiver
    if self.settings[:k]
      self.settings[:k]
    end
  end

  def receiver_with_arguments
    if lookup(1)[:k]
      lookup(1)[:k]
    end
  end

  def receiver_with_block(rows)
    if rows.map { |row| row }[0]
      rows.map { |row| row }[0]
    end
  end

  def nested_index(config)
    if config[:font]
      config[:font][:size]
    end
  end

  def reassigned(config)
    if config[:k]
      config = {}
      config[:k]
    end
  end

  def or_assigned(config)
    if config[:k]
      config ||= {}
      config[:k]
    end
  end

  def multi_assigned(config)
    if config[:k]
      config, other = {}, 1
      [config[:k], other]
    end
  end

  def ivar_reassigned
    if @config[:k]
      @config = {}
      @config[:k]
    end
  end

  def chain_root_reassigned(user)
    if user.settings[:k]
      user = nil
      user.settings[:k]
    end
  end

  def other_variable_assigned(config)
    if config[:k]
      other = 1
      [config[:k], other]
    end
  end

  def deleted(config)
    if config[:k]
      config.delete(:k)
      config[:k]
    end
  end

  def index_assigned(config)
    if config[:k]
      config[:k] = nil
      config[:k]
    end
  end

  def bang_mutated(config)
    if config[:k]
      config.compact!
      config[:k]
    end
  end

  def other_receiver_mutated(config, other)
    if config[:k]
      other.delete(:k)
      config[:k]
    end
  end

  def read_only_call(config)
    if config[:k]
      config.size
      config[:k]
    end
  end

  def inside_block(config, items)
    if config[:k]
      items.each { |item| item << config[:k] }
    end
  end

  def shadowed_by_block_parameter(config, items)
    if config[:k]
      items.each { |config| config[:k] }
    end
  end

  def inside_lambda(config)
    if config[:k]
      -> { config[:k] }
    end
  end

  def inside_nested_def
    if settings[:k]
      def helper
        settings[:k]
      end
    end
  end

  def settings = {}

  def lookup(_id) = {}
end
