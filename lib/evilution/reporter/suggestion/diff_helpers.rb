# frozen_string_literal: true

require_relative "../suggestion"

module Evilution::Reporter::Suggestion::DiffHelpers
  module_function

  def parse_method_name(subject_name)
    subject_name.split(/[#.]/).last
  end

  def sanitize_method_name(name)
    name.gsub(/[^a-zA-Z0-9_]/, "_").gsub(/_+/, "_").gsub(/\A_|_\z/, "")
  end
end
