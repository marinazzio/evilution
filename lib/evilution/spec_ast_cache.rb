# frozen_string_literal: true

require "prism"
require_relative "../evilution"

class Evilution::SpecAstCache
  Block = Struct.new(:kind, :line, :end_line, :body_text)

  BLOCK_METHODS = %i[
    describe context fcontext xcontext
    it fit xit specify
    before after
  ].freeze
  private_constant :BLOCK_METHODS

  DEFAULT_MAX_FILES = 50
  DEFAULT_MAX_BLOCKS = 10_000
  private_constant :DEFAULT_MAX_FILES, :DEFAULT_MAX_BLOCKS

  def initialize(max_files: DEFAULT_MAX_FILES, max_blocks: DEFAULT_MAX_BLOCKS)
    @max_files = max_files
    @max_blocks = max_blocks
    @entries = {}
    @total_blocks = 0
  end

  def fetch(path)
    if @entries.key?(path)
      blocks = @entries.delete(path)
      @entries[path] = blocks
      return blocks
    end

    blocks = parse(path)
    insert(path, blocks)
    blocks
  end

  def cached?(path)
    @entries.key?(path)
  end

  private

  def insert(path, blocks)
    @entries[path] = blocks
    @total_blocks += blocks.length
    evict_until_within_bounds
  end

  def evict_until_within_bounds
    while @entries.length > @max_files || @total_blocks > @max_blocks
      break if @entries.empty?

      oldest_path = @entries.keys.first
      evicted = @entries.delete(oldest_path)
      @total_blocks -= evicted.length
    end
  end

  def parse(path)
    raise Evilution::ParseError.new("file not found: #{path}", file: path) unless File.exist?(path)

    source = read_source(path)
    result = Prism.parse(source)

    if result.failure?
      raise Evilution::ParseError.new(
        "failed to parse #{path}: #{result.errors.map(&:message).join(", ")}",
        file: path
      )
    end

    comment_ranges = result.comments
                           .map { |c| c.location.start_offset...c.location.end_offset }
                           .sort_by(&:begin)
    collector = BlockCollector.new(source, comment_ranges)
    collector.visit(result.value)
    collector.blocks
  end

  def read_source(path)
    File.read(path)
  rescue SystemCallError => e
    raise Evilution::ParseError.new("cannot read #{path}: #{e.message}", file: path)
  end

  class BlockCollector < Prism::Visitor
    attr_reader :blocks

    def initialize(source, comment_ranges)
      @source = source
      @comment_ranges = comment_ranges
      @blocks = []
      super()
    end

    def visit_call_node(node)
      @blocks << build_block(node) if block_method?(node)
      super
    end

    private

    def block_method?(node)
      BLOCK_METHODS.include?(node.name) && node.block
    end

    def build_block(node)
      location = node.location
      Block.new(
        node.name,
        location.start_line,
        location.end_line,
        extract_body_text(node)
      )
    end

    def extract_body_text(node)
      block = node.block
      return "" unless block

      body = block.body
      return "" unless body

      start_off = body.location.start_offset
      end_off = body.location.end_offset
      slice = @source.byteslice(start_off, end_off - start_off) || ""
      stripped = strip_comments(slice, start_off)
      stripped.downcase
    end

    def strip_comments(slice, base_offset)
      return slice if @comment_ranges.empty?

      ranges = comment_ranges_within(base_offset, base_offset + slice.bytesize)
      return slice if ranges.empty?

      result = +""
      cursor = base_offset
      ranges.each do |range|
        result << @source.byteslice(cursor, range.begin - cursor)
        cursor = range.end
      end
      result << @source.byteslice(cursor, base_offset + slice.bytesize - cursor)
      result
    end

    def comment_ranges_within(start_off, end_off)
      lower = @comment_ranges.bsearch_index { |r| r.begin >= start_off }
      return [] unless lower

      result = []
      idx = lower
      while idx < @comment_ranges.length
        range = @comment_ranges[idx]
        break if range.begin >= end_off

        result << range if range.end <= end_off
        idx += 1
      end
      result
    end
  end
  private_constant :BlockCollector
end
