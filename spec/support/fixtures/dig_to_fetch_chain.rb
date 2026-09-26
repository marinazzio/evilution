class DigToFetchChainTarget
  def two_keys(config)
    config.dig(:db, :host)
  end

  def three_keys(config)
    config.dig(:db, :primary, :host)
  end

  def without_parens(config)
    config.dig :db, :host
  end

  def safe_navigation(config)
    config&.dig(:db, :host)
  end

  def single_key(config)
    config.dig(:db)
  end

  def splat(config, keys)
    config.dig(*keys)
  end

  def receiverless
    dig(:db, :host)
  end

  def other_method(config)
    config.fetch(:db, :host)
  end
end
