# frozen_string_literal: true

module Evilution::MCP
  # Public contract version for the evilution MCP tool surface (input schemas,
  # output payload shapes, error envelope, action enumerations). Bumped only
  # at MAJOR releases per docs/versioning.md. Independent of session JSON
  # schema versioning (Evilution::Session::Schema) so the two surfaces can
  # rev separately.
  CONTRACT_VERSION = 1
end
