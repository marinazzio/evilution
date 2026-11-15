# frozen_string_literal: true

require_relative "../config"
require_relative "file_loader"
require_relative "env_loader"

module Evilution::Config::Sources
  module_function

  # timeout_given: whether the file or the caller set a timeout, which then
  # applies to every mutation instead of one derived from the baseline.
  def merge(explicit:, skip_file:)
    file = skip_file ? {} : Evilution::Config::FileLoader.load
    env  = Evilution::Config::EnvLoader.load
    Evilution::Config::DEFAULTS.merge(file).merge(env).merge(explicit)
                               .merge(timeout_given: file.key?(:timeout) || explicit.key?(:timeout))
  end
end
