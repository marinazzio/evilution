# frozen_string_literal: true

require_relative "../html"

module Evilution::Reporter::HTML::Stylesheet
  PATH = File.expand_path("assets/style.css", __dir__)
  CSS = File.read(PATH).freeze

  module_function

  def call
    "<style>\n#{CSS}</style>"
  end
end
