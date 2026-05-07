# frozen_string_literal: true

require "yaml"

module Evilution::Config::FileLoader
  module_function

  KNOWN_KEYS = (Evilution::Config::DEFAULTS.keys + %i[hooks target_files]).uniq.freeze

  def load
    Evilution::Config::CONFIG_FILES.each do |path|
      next unless File.exist?(path)

      data = YAML.safe_load_file(path, symbolize_names: true)
      return {} unless data.is_a?(Hash)

      validate_schema!(data, path: path) if data.key?(:schema_version)
      return data
    rescue Psych::SyntaxError, Psych::DisallowedClass => e
      raise Evilution::ConfigError.new("failed to parse config file #{path}: #{e.message}", file: path)
    rescue SystemCallError => e
      raise Evilution::ConfigError.new("cannot read config file #{path}: #{e.message}", file: path)
    end

    {}
  end

  def validate_schema!(data, path:)
    validate_schema_version_value!(data[:schema_version], path: path)
    validate_known_keys!(data.keys, path: path)
  end

  def validate_schema_version_value!(version, path:)
    unless version.is_a?(Integer) && version.positive?
      raise Evilution::ConfigError.new(
        "invalid schema_version #{version.inspect} in #{path}: must be a positive Integer",
        file: path
      )
    end

    return if version <= Evilution::Config::CURRENT_SCHEMA_VERSION

    raise Evilution::ConfigError.new(
      "schema_version #{version} in #{path} is newer than this evilution gem supports " \
      "(current: #{Evilution::Config::CURRENT_SCHEMA_VERSION}). Upgrade the gem.",
      file: path
    )
  end

  def validate_known_keys!(keys, path:)
    unknown = keys - KNOWN_KEYS
    return if unknown.empty?

    raise Evilution::ConfigError.new(
      "unknown key(s) #{unknown.inspect} in #{path}. Known keys: #{KNOWN_KEYS.sort.inspect}",
      file: path
    )
  end
end
