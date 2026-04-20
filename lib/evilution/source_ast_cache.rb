# frozen_string_literal: true

require "digest"
require "prism"
require_relative "../evilution"

# Content-hash-keyed LRU of Prism::ParseResult. Different source bytes always
# yield a different key, so the cache is valid for the lifetime of the process.
class Evilution::SourceAstCache
  DEFAULT_MAX_ENTRIES = 50
  private_constant :DEFAULT_MAX_ENTRIES

  def initialize(max_entries: DEFAULT_MAX_ENTRIES)
    @max_entries = max_entries
    @entries = {}
  end

  def fetch(source)
    key = Digest::SHA256.hexdigest(source)
    if @entries.key?(key)
      result = @entries.delete(key)
      @entries[key] = result
      return result
    end

    result = Prism.parse(source)
    @entries[key] = result
    evict_until_within_bounds
    result
  end

  private

  def evict_until_within_bounds
    while @entries.length > @max_entries
      break if @entries.empty?

      oldest = @entries.keys.first
      @entries.delete(oldest)
    end
  end
end
