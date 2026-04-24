# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::SpecMappings < Evilution::Config::Validators::Base
  def self.call(value)
    return {} if value.nil?

    raise Evilution::ConfigError, "spec_mappings must be a Hash, got #{value.class}" unless value.is_a?(Hash)

    normalized = value.each_with_object({}) do |(source, specs), acc|
      key = normalize_key(source)
      acc[key] = normalize_value(key, specs)
    end

    warn_missing(normalized)
    normalized
  end

  class << self
    private

    def normalize_key(source)
      key = source.to_s
      key = key.delete_prefix("#{Dir.pwd}/") if key.start_with?("/")
      key.delete_prefix("./")
    end

    def normalize_value(source, specs)
      case specs
      when String then [specs]
      when Array
        specs.each do |entry|
          unless entry.is_a?(String)
            raise Evilution::ConfigError,
                  "spec_mappings[#{source.inspect}] entries must be string paths, got #{entry.class}"
          end
        end
        specs
      else
        raise Evilution::ConfigError,
              "spec_mappings[#{source.inspect}] must be a string or array of strings, got #{specs.class}"
      end
    end

    def warn_missing(mappings)
      mappings.each do |source, specs|
        specs.each do |spec_path|
          next if File.exist?(spec_path)

          warn "[evilution] spec_mappings[#{source.inspect}]: #{spec_path} not found, skipping"
        end
      end
    end
  end
end
