# frozen_string_literal: true

require_relative "../load_path"

# Given an absolute (or expandable) file path, returns the shortest path
# relative to any `$LOAD_PATH` entry the file lives under, or nil if the file
# is outside every entry. The shortest match wins because a deeper LOAD_PATH
# entry yields a shorter subpath that better matches `require` resolution.
class Evilution::LoadPath::SubpathResolver
  def call(file_path)
    absolute = File.expand_path(file_path)
    best_subpath = nil

    $LOAD_PATH.each do |entry|
      dir = File.expand_path(entry)
      prefix = dir.end_with?("/") ? dir : "#{dir}/"
      next unless absolute.start_with?(prefix)

      candidate = absolute.delete_prefix(prefix)
      best_subpath = candidate if best_subpath.nil? || candidate.length < best_subpath.length
    end

    best_subpath
  end
end
