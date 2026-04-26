# frozen_string_literal: true

require_relative "../feedback"

module Evilution::Feedback::Detector
  module_function

  def friction?(summary)
    return false if summary.nil?

    summary.errors.positive? ||
      summary.unparseable.positive? ||
      summary.unresolved.positive?
  end
end
