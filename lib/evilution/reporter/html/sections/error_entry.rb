# frozen_string_literal: true

require_relative "../sections"
require_relative "../diff_formatter"

class Evilution::Reporter::HTML::Sections::ErrorEntry < Evilution::Reporter::HTML::Section
  template "error_entry"

  def initialize(result)
    @result = result
  end

  private

  def message
    @result.error_message.to_s
  end

  def diff_html
    Evilution::Reporter::HTML::DiffFormatter.call(@result.mutation.diff)
  end
end
