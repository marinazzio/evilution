# frozen_string_literal: true

require_relative "namespace"
require_relative "escape"

module Evilution::Reporter::HTML::DiffFormatter
  module_function

  def call(diff)
    diff.split("\n").map { |line| format_line(line) }.join("\n")
  end

  def format_line(line)
    css_class = line_class(line)
    %(<span class="#{css_class}">#{Evilution::Reporter::HTML::Escape.call(line)}</span>)
  end

  def line_class(line)
    if line.start_with?("- ")
      "diff-removed"
    elsif line.start_with?("+ ")
      "diff-added"
    else
      ""
    end
  end
end
