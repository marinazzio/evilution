# frozen_string_literal: true

# version.rb defines the Evilution module, so any MCP file can be the first
# one required.
require_relative "version"

module Evilution::MCP
  # Public contract version for the evilution MCP tool surface (input schemas,
  # output payload shapes, error envelope, action enumerations). Bumped only
  # at MAJOR releases per docs/versioning.md. Independent of session JSON
  # schema versioning (Evilution::Session::Schema) so the two surfaces can
  # rev separately.
  CONTRACT_VERSION = 1
end
