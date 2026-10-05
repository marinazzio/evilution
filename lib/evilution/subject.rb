# frozen_string_literal: true

# What mutations are generated for and reported against. A :method subject is
# a method definition; a :constant subject is a definition assigned to a
# constant outside any method, such as `Point = Data.define(:x, :y)`.
class Evilution::Subject
  attr_reader :name, :file_path, :line_number, :source, :node, :kind

  def initialize(name:, file_path:, line_number:, source:, node:, kind: :method)
    @name = name
    @file_path = file_path
    @line_number = line_number
    @source = source
    @node = node
    @kind = kind
  end

  def release_node!
    @node = nil
  end

  def to_s
    "#{name} (#{file_path}:#{line_number})"
  end
end
