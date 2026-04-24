# frozen_string_literal: true

require_relative "base"

class Evilution::Config::Validators::IgnorePatterns < Evilution::Config::Validators::Base
  def self.call(value)
    patterns = Array(value)
    patterns.each do |pattern|
      unless pattern.is_a?(String)
        raise Evilution::ConfigError,
              "ignore_patterns must be an array of strings, got #{pattern.class} (#{pattern.inspect})"
      end
    end
    patterns
  end
end
