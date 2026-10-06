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

  def parenthesized_sequence_ending_elsewhere(config, enabled)
    if (config[:k]; enabled)
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

  # Early exits: the guard and the read are sibling statements.

  def return_unless(config)
    return unless config[:k]

    config[:k]
  end

  def return_value_unless(config)
    return :none unless config[:k]

    config[:k]
  end

  def raise_unless(config)
    raise ArgumentError, "no k" unless config[:k]

    config[:k]
  end

  def fail_unless(config)
    fail "no k" unless config[:k]

    config[:k]
  end

  def block_unless(config, log)
    unless config[:k]
      log << :missing
      return
    end

    config[:k]
  end

  def unless_without_exit(config, log)
    log << :missing unless config[:k]

    config[:k]
  end

  def unless_exit_not_last(config, log)
    unless config[:k]
      return if log
      log << :missing
    end

    config[:k]
  end

  def unless_with_else(config)
    unless config[:k]
      return
    else
      config[:k]
    end

    config[:k]
  end

  def return_if_nil(config)
    return if config[:k].nil?

    config[:k]
  end

  def return_if_blank(config)
    return if config[:k].blank?

    config[:k]
  end

  def return_if_negated(config)
    return if !config[:k]

    config[:k]
  end

  def return_if_not(config)
    return if not config[:k]

    config[:k]
  end

  def return_if_key_missing(config)
    return unless config.key?(:k)

    config[:k]
  end

  def return_if_negated_key(config)
    return if !config.key?(:k)

    config[:k]
  end

  def return_if_nil_or_other(config, other)
    return if other || config[:k].nil?

    config[:k]
  end

  def return_if_nil_and_other(config, other)
    return if other && config[:k].nil?

    config[:k]
  end

  def return_if_present(config)
    return if config[:k]

    config[:k]
  end

  def return_if_empty(config)
    return if config[:k].empty?

    config[:k]
  end

  def return_unless_conjunct(config, enabled)
    return unless enabled && config[:k]

    config[:k]
  end

  def return_unless_disjunct(config, enabled)
    return unless enabled || config[:k]

    config[:k]
  end

  def if_block_exit(config)
    if config[:k].nil?
      return
    end

    config[:k]
  end

  def if_exit_with_else(config, log)
    if config[:k].nil?
      return
    else
      log << :present
    end

    config[:k]
  end

  def or_return(config)
    config[:k] or return

    config[:k]
  end

  def double_pipe_raise(config)
    config[:k] || raise(KeyError)

    config[:k]
  end

  def and_return(config)
    config[:k] and return

    config[:k]
  end

  def next_unless(config, items)
    items.map do |item|
      next unless config[:k]

      item + config[:k]
    end
  end

  def break_unless(config, items)
    items.each do |item|
      break unless config[:k]

      item << config[:k]
    end
  end

  def return_if_other_read_nil(config)
    return if config[:other].nil?

    config[:k]
  end

  def return_if_not_other(config, other)
    return if !other

    config[:k]
  end

  def return_if_unrelated_or(config, other, another)
    return if other || another

    config[:k]
  end

  def return_if_parenthesized_other(config, other)
    return if (other)

    config[:k]
  end

  def return_if_nil_first_or_other(config, other)
    return if config[:k].nil? || other

    config[:k]
  end

  def return_if_parenthesized_nil(config)
    return if (config[:k].nil?)

    config[:k]
  end

  def return_if_parenthesized_sequence(config, other)
    return if (config[:k].nil?; other)

    config[:k]
  end

  def or_without_exit(config, log)
    config[:k] or log.push(:missing)

    config[:k]
  end

  def or_exit_on_other(config, other)
    other or return

    config[:k]
  end

  def raise_on_receiver_unless(config, log)
    log.raise unless config[:k]

    config[:k]
  end

  def bare_call_unless(config)
    warn "missing" unless config[:k]

    config[:k]
  end

  def empty_unless(config)
    unless config[:k]
    end

    config[:k]
  end

  def guard_that_cleans_up_before_leaving(config)
    unless config[:k]
      config.clear
      return
    end

    config[:k]
  end

  def guarded_again_after_a_change(config)
    return unless config[:k]

    config.clear
    return unless config[:k]

    config[:k]
  end

  def read_before_guard(config)
    value = config[:k]
    return unless config[:k]

    value
  end

  def read_in_later_branch(config, other)
    return unless config[:k]

    if other
      other << config[:k]
    end
  end

  def read_in_later_block(config, items)
    return unless config[:k]

    items.each { |item| item << config[:k] }
  end

  def guard_in_outer_list(config, other)
    return unless config[:k]

    if other
      other.clear
      other << config[:k]
    end
  end

  def guard_in_inner_list_only(config, other)
    if other
      return unless config[:k]
    end

    config[:k]
  end

  def guard_in_earlier_block(config, items)
    items.each do |_item|
      next unless config[:k]
    end

    config[:k]
  end

  def exit_guard_other_key(config)
    return unless config[:a]

    config[:b]
  end

  def reassigned_after_guard(config)
    return unless config[:k]

    config = {}
    config[:k]
  end

  def mutated_after_guard(config)
    return unless config[:k]

    config.delete(:k)
    config[:k]
  end

  def mutated_in_read_statement(config, items)
    return unless config[:k]

    items.each do |item|
      item << config[:k]
      config.clear
    end
  end

  def mutated_after_read(config)
    return unless config[:k]

    value = config[:k]
    config.clear
    value
  end

  def read_in_lambda_after_guard(config)
    return unless config[:k]

    -> { config[:k] }
  end

  def read_in_rescue_after_guard(config)
    return unless config[:k]

    yield
  rescue StandardError
    config[:k]
  end

  def guard_then_shadowing_block(config, items)
    return unless config[:k]

    items.each { |config| config[:k] }
  end

  def settings = {}

  def lookup(_id) = {}
end
