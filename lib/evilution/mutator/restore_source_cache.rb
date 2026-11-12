# frozen_string_literal: true

require_relative "../mutator"

# The restore source of a subject with no declaration of its own to keep is
# the same for every mutation of the file: neutralized once and shared. A
# file is neutralized again when its source differs from the cached one.
module Evilution::Mutator::RestoreSourceCache
  Entry = Data.define(:source_hash, :source)
  private_constant :Entry

  @sources = {}

  def self.source_for(file_path, file_source, neutralizer)
    entry = @sources[file_path]
    return entry.source if entry && entry.source_hash == file_source.hash

    source = neutralizer.call(file_source, file_path: file_path).freeze
    @sources[file_path] = Entry.new(source_hash: file_source.hash, source: source)
    source
  end

  def self.clear!
    @sources = {}
  end
end
