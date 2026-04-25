# frozen_string_literal: true

require_relative "../cli"

class Evilution::Reporter::CLI::Section
  attr_reader :title, :fetcher, :formatter

  def initialize(title:, fetcher:, formatter:)
    @title = title
    @fetcher = fetcher
    @formatter = formatter
  end
end
