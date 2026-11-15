# frozen_string_literal: true

require_relative "../mutator"

# A file's neutralization, built once for all the mutations of the file: its
# source is the restore source of every subject with no declaration of its
# own to keep, and its edits let a mutation be carried into it (see
# Integration::Loading::Neutralization). A file is neutralized again when
# its source differs from the cached one; the very source object it was
# built from is recognised without hashing it again.
module Evilution::Mutator::RestoreSourceCache
  Entry = Data.define(:file_source, :source_hash, :neutralization)
  private_constant :Entry

  @entries = {}

  def self.source_for(file_path, file_source, neutralizer)
    neutralization_for(file_path, file_source, neutralizer).source
  end

  def self.neutralization_for(file_path, file_source, neutralizer)
    entry = @entries[file_path]
    return entry.neutralization if entry && current?(entry, file_source)

    neutralization = neutralizer.neutralization(file_source, file_path: file_path)
    neutralization.source.freeze
    @entries[file_path] = Entry.new(file_source: file_source, source_hash: file_source.hash,
                                    neutralization: neutralization)
    neutralization
  end

  def self.current?(entry, file_source)
    entry.file_source.equal?(file_source) || entry.source_hash == file_source.hash
  end

  def self.clear!
    @entries = {}
  end

  private_class_method :current?
end
