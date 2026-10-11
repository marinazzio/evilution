class ConstantNamespaceStripTarget
  def constant_path
    Config::LIMIT
  end

  def nested_constant_path
    App::Config::LIMIT
  end

  def call_receiver
    Reports::Builder.new
  end

  def as_argument(value)
    value.is_a?(Errors::Timeout)
  end

  def assigned
    limit = Config::LIMIT
    limit
  end

  def rescue_class
    run
  rescue Errors::Timeout
    retry_later
  end

  def dynamic_namespace
    self.class::LIMIT
  end

  def anchored_namespace
    ::Config::LIMIT
  end

  def top_level_path
    ::LIMIT
  end

  def bare_constant
    LIMIT
  end

  def namespaced_call
    Config::limit
  end

  def path_or_write(value)
    Config::LIMIT ||= value
  end
end
