# frozen_string_literal: true

class Evilution::Subject
  attr_reader :name, :file_path, :line_number, :source, :node

  def initialize(name:, file_path:, line_number:, source:, node:)
    @name = name
    @file_path = file_path
    @line_number = line_number
    @source = source
    @node = node
  end

  def release_node!
    @node = nil
  end

  def to_s
    "#{name} (#{file_path}:#{line_number})"
  end
end
