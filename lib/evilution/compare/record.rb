# frozen_string_literal: true

require_relative "../compare"

module Evilution::Compare
  Record = Data.define(
    :source,
    :file_path,
    :line,
    :status,
    :fingerprint,
    :operator,
    :diff_body,
    :raw
  )
end
