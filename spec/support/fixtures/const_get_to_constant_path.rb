class ConstGetTarget
  def plain
    Registry.const_get(:Handler)
  end

  def namespaced_receiver
    Acme::Plugins.const_get(:Loader)
  end

  def without_inherit
    Registry.const_get(:Handler, false)
  end

  def with_inherit
    Registry.const_get(:Handler, true)
  end

  def variable_receiver(klass)
    klass.const_get(:Config)
  end

  def receiverless
    const_get(:Handler)
  end

  def string_name
    Registry.const_get("Handler")
  end

  def dynamic_name(name)
    Registry.const_get(name)
  end

  def lowercase_symbol
    Registry.const_get(:handler)
  end

  def safe_navigation(klass)
    klass&.const_get(:Config)
  end

  def dynamic_inherit(flag)
    Registry.const_get(:Handler, flag)
  end
end
