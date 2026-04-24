# frozen_string_literal: true

require "yaml"

module Evilution::Config::FileLoader
  module_function

  def load
    Evilution::Config::CONFIG_FILES.each do |path|
      next unless File.exist?(path)

      data = YAML.safe_load_file(path, symbolize_names: true)
      return data.is_a?(Hash) ? data : {}
    rescue Psych::SyntaxError, Psych::DisallowedClass => e
      raise Evilution::ConfigError.new("failed to parse config file #{path}: #{e.message}", file: path)
    rescue SystemCallError => e
      raise Evilution::ConfigError.new("cannot read config file #{path}: #{e.message}", file: path)
    end

    {}
  end
end
