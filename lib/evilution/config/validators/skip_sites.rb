# frozen_string_literal: true

require_relative "../validators"
require_relative "base"
require_relative "../../ast/skip_sites/presets"

# `skip_sites` names the presets of low-value code to leave unmutated (see
# AST::SkipSites::Presets). `false` is accepted as none.
class Evilution::Config::Validators::SkipSites < Evilution::Config::Validators::Base
  def self.call(value)
    return [] if value == false

    Array(value).map { |name| preset_name!(name) }.uniq
  end

  def self.preset_name!(name)
    known = Evilution::AST::SkipSites::Presets.names
    symbol = name.to_sym if name.is_a?(String) || name.is_a?(Symbol)
    return symbol if known.include?(symbol)

    raise Evilution::ConfigError, "skip_sites: unknown preset #{name.inspect} (known: #{known.join(", ")})"
  end
  private_class_method :preset_name!
end
