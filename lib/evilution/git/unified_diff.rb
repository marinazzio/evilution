# frozen_string_literal: true

require_relative "../git"
require_relative "../line_set"

# Reads the new-file lines each hunk of `git diff -U0` output touches, per
# file: { path => Evilution::LineSet }. Expects git's default `b/` prefix on
# the new file's name.
#
# A line starting with `diff --git ` or `@@ ` is always a header: every
# content line of a hunk starts with `+`, `-`, a space or `\`. A file's `+++`
# line is read only between its `diff --git` line and its first hunk, where an
# added line that happens to start with `++` cannot be.
#
# Lines that were only deleted leave no line of their own behind; the lines
# either side of the gap count instead.
class Evilution::Git::UnifiedDiff
  HUNK_HEADER = /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/
  ESCAPES = { "a" => "\a", "b" => "\b", "t" => "\t", "n" => "\n", "v" => "\v", "f" => "\f", "r" => "\r" }.freeze
  private_constant :HUNK_HEADER, :ESCAPES

  def self.parse(output)
    new.parse(output)
  end

  def parse(output)
    @changed = Hash.new { |changed, path| changed[path] = [] }
    @path = nil
    @in_header = false
    output.each_line(chomp: true) { |line| read(line) }
    @changed.transform_values { |ranges| Evilution::LineSet.new(ranges) }
  end

  private

  def read(line)
    if line.start_with?("diff --git ")
      @path = nil
      @in_header = true
    elsif @in_header && line.start_with?("+++ ")
      @path = new_path(line.delete_prefix("+++ "))
    elsif (hunk = HUNK_HEADER.match(line))
      read_hunk(Integer(hunk[1]), hunk[2] ? Integer(hunk[2]) : 1)
    end
  end

  def read_hunk(start, count)
    @in_header = false
    return if @path.nil?

    @changed[@path] << (count.zero? ? ([start, 1].max..(start + 1)) : (start..(start + count - 1)))
  end

  # `+++ b/path`, quoted C-style when the path holds a quote, a backslash or a
  # control character; a path holding a space ends in a tab instead.
  def new_path(text)
    text = text.chomp("\t")
    text = unquote(text) if text.start_with?('"')
    text.delete_prefix("b/").dup.force_encoding(Encoding::UTF_8)
  end

  def unquote(text)
    text[1...-1].b.gsub(/\\(?:([0-7]{3})|(.))/m) do
      octal = Regexp.last_match(1)
      octal ? octal.to_i(8).chr : ESCAPES.fetch(Regexp.last_match(2), Regexp.last_match(2))
    end
  end
end
