class DynamicDispatchTarget
  def explicit_send(target)
    target.send(:reset)
  end

  def send_with_arguments(target, a, b)
    target.send(:update, a, b)
  end

  def underscore_send(target)
    target.__send__(:reset)
  end

  def send_without_parens(target, value)
    target.send :store, value
  end

  def send_with_block_pass(target, block)
    target.send(:each, &block)
  end

  def send_with_literal_block(target)
    target.send(:each) { |item| item }
  end

  def safe_send(target)
    target&.send(:reset)
  end

  def implicit_send
    send(:reset)
  end

  def self_send
    self.send(:reset)
  end

  def implicit_public_send(value)
    public_send(:store, value)
  end

  def self_public_send
    self.public_send(:reset)
  end

  def explicit_public_send(target)
    target.public_send(:reset)
  end

  def string_selector(target)
    target.send("reset")
  end

  def dynamic_selector(target, name)
    target.send(name)
  end

  def splat_selector(target, args)
    target.send(*args)
  end
end
