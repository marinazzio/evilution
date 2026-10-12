class VariableReadToNilTarget
  def local_variable(value)
    value
  end

  def instance_variable
    @name
  end

  def class_variable
    @@count
  end

  def global_variable
    $verbose
  end

  def self_reference
    self
  end

  def assigned(value)
    copy = value
    copy.size
  end

  def keyword_argument(value)
    build(name: value)
  end

  def array_elements(first, second)
    [first, second]
  end

  def hash_value(value)
    { key: value }
  end

  def right_operand(left, right)
    left && right
  end

  def case_subject(value)
    case value
    when 1 then :one
    else :other
    end
  end

  def block_local(items)
    items.map { |item| item }
  end

  def splat(items)
    build(*items)
  end

  def call_receiver(user)
    user.name
  end

  def self_receiver
    self.name
  end

  def chained_receiver
    @user.profile.name
  end

  def void_statement(value)
    value
    1
  end

  def condition(flag, yes, no)
    flag ? yes : no
  end

  def modifier_condition(flag, value)
    value if flag
  end

  def unless_condition(flag, value)
    value unless flag
  end

  def loop_condition(flag, value)
    total = value while flag
  end

  def until_condition(flag, value)
    total = value until flag
  end

  def and_operands(left, right)
    left && right
  end

  def or_operands(left, right)
    left || right
  end

  def block_pass(items, limit, callable)
    items.first(limit, &callable)
  end

  def double_splat(name, options)
    build(name, **options)
  end

  def block_pass_expression(items, handlers, key)
    items.each(&handlers[key])
  end

  def double_splat_expression(defaults, extra)
    build(**defaults.merge(extra))
  end

  def shorthand_hash(name)
    build(name:)
  end

  def writes_only(value)
    @stored = 1
    total = 2
    total += 3
    @stored ||= 4
  end

  def no_variables
    compute(1)
  end

  def operator_write_receiver(counter, step)
    counter.total += step
  end

  def or_write_receiver(user, name)
    user.name ||= name
  end

  def and_write_receiver(user, name)
    user.name &&= name
  end

  def index_operator_write_receiver(counts, key, step)
    counts[key] += step
  end

  def index_or_write_receiver(cache, key, value)
    cache[key] ||= value
  end

  def index_and_write_receiver(cache, key, value)
    cache[key] &&= value
  end

  def multiple_assignment_receivers(account, store, key, pair)
    account.owner, store[key] = pair
    account
  end

  def attribute_target_receiver_expression(registry, name, pair)
    registry[name].owner, other = pair
    other.to_s
  end

  def self.singleton_on_self(value)
    value
  end

  def singleton_on_local(target, value)
    def target.extra(input) = input
    value
  end

  def singleton_class_of_self(value)
    class << self
      @settings = $defaults
    end
    value
  end
end
