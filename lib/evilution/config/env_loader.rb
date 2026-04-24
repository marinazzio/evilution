# frozen_string_literal: true

module Evilution::Config::EnvLoader
  module_function

  def load
    opts = {}
    val = ENV.fetch("EV_DISABLE_EXAMPLE_TARGETING", nil)
    opts[:example_targeting] = false if val && !val.empty? && val != "0"
    opts
  end
end
