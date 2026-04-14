# frozen_string_literal: true

require "cgi"
require_relative "namespace"

module Evilution::Reporter::HTML::Escape
  module_function

  def call(text)
    CGI.escapeHTML(text.to_s)
  end
end
