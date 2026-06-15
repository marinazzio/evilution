# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../coverage"
require_relative "map"
require_relative "digest"

# Disk cache for a per-example coverage Map under .evilution/coverage/, keyed by
# a per-file content digest so a map survives across runs and invalidates one
# file at a time.
#
# load is partial: it returns a Map pruned to the files whose on-disk content
# still matches the cached digest. A stale or deleted file is dropped (so its
# `built?` is false and the caller falls back to lexical targeting) while every
# fresh file stays queryable. A missing or corrupt cache returns nil, signalling
# the caller to rebuild from scratch.
class Evilution::Coverage::MapStore
  DEFAULT_ROOT = ".evilution/coverage"
  CACHE_FILE = "map.json"

  def initialize(root: DEFAULT_ROOT, digest: Evilution::Coverage::Digest.new)
    @root = root
    @digest = digest
  end

  def save(map, source_files)
    payload = { "digests" => digests_for(source_files), "map" => map.to_h }
    FileUtils.mkdir_p(@root)
    File.write(cache_path, JSON.generate(payload))
  end

  def load(source_files)
    payload = read_payload
    return nil unless payload

    cached_digests = payload["digests"] || {}
    fresh = source_files.select { |file| fresh?(file, cached_digests) }
    pruned_map(payload["map"] || {}, fresh)
  end

  # Source files whose on-disk content no longer matches the cache (changed,
  # deleted, or never cached) -- the caller rebuilds these. Every file is stale
  # when there is no cache at all.
  def stale_files(source_files)
    payload = read_payload
    return source_files.dup unless payload

    cached_digests = payload["digests"] || {}
    source_files.reject { |file| fresh?(file, cached_digests) }
  end

  private

  def fresh?(file, cached_digests)
    cached = cached_digests[file]
    !cached.nil? && cached == @digest.for_file(file)
  end

  def pruned_map(raw_map, fresh_files)
    index = (raw_map["index"] || {}).slice(*fresh_files)
    built = (raw_map["built_files"] || []) & fresh_files
    executed = (raw_map["executed_lines"] || {}).slice(*fresh_files)
    Evilution::Coverage::Map.from_h(
      "index" => index, "built_files" => built, "executed_lines" => executed
    )
  end

  def digests_for(source_files)
    source_files.each_with_object({}) do |file, out|
      digest = @digest.for_file(file)
      out[file] = digest unless digest.nil?
    end
  end

  def read_payload
    return nil unless File.file?(cache_path)

    JSON.parse(File.read(cache_path))
  rescue JSON::ParserError, Errno::ENOENT
    nil
  end

  def cache_path
    File.join(@root, CACHE_FILE)
  end
end
