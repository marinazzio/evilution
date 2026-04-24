# frozen_string_literal: true

require_relative "file_loader"
require_relative "env_loader"

module Evilution::Config::Sources
  module_function

  def merge(explicit:, skip_file:)
    file = skip_file ? {} : Evilution::Config::FileLoader.load
    env  = Evilution::Config::EnvLoader.load
    Evilution::Config::DEFAULTS.merge(file).merge(env).merge(explicit)
  end
end
