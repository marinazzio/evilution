# frozen_string_literal: true

module Evilution
  class Subject
    attr_reader :name, :file_path, :line_number, :source, :node

    def initialize(name:, file_path:, line_number:, source:, node:)
      @name = name
      @file_path = file_path
      @line_number = line_number
      @source = source
      @node = node
      freeze
    end

    def to_s
      "#{name} (#{file_path}:#{line_number})"
    end
  end
end
