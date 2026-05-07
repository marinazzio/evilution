# frozen_string_literal: true

require_relative "../session"

module Evilution::Session::Schema
  CURRENT_VERSION = 1

  module_function

  # Validates the schema_version of a parsed session JSON Hash.
  #
  # Sessions written before schema_version was introduced are treated as
  # CURRENT_VERSION (the JSON shape that defined version 1). A session with a
  # schema_version newer than this gem supports raises Evilution::Error with
  # an explicit "upgrade the gem" message — silent misreads would corrupt
  # compare/diff output.
  def validate!(data, source: nil)
    raw = data["schema_version"] || data[:schema_version]
    return if raw.nil?

    raise_invalid!(raw, source) unless raw.is_a?(Integer) && raw.positive?
    return if raw <= CURRENT_VERSION

    raise_future!(raw, source)
  end

  def raise_invalid!(value, source)
    raise Evilution::Error,
          "invalid schema_version #{value.inspect}#{location_clause(source)}: must be a positive Integer"
  end

  def raise_future!(value, source)
    raise Evilution::Error,
          "session file#{location_clause(source)} has schema_version #{value}, " \
          "newer than this evilution gem supports (current: #{CURRENT_VERSION}). " \
          "Upgrade the evilution gem."
  end

  def location_clause(source)
    source ? " at #{source}" : ""
  end
end
