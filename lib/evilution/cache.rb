# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"

module Evilution
  class Cache
    DEFAULT_DIR = "tmp/evilution_cache"

    def initialize(cache_dir: DEFAULT_DIR)
      @cache_dir = cache_dir
    end

    def fetch(mutation)
      return nil if mutation.original_source.nil?

      file_key = file_key(mutation)
      entry_key = entry_key(mutation)
      data = read_file(file_key)
      return nil unless data

      entry = data[entry_key]
      return nil unless entry.is_a?(Hash) && entry["status"].is_a?(String)

      { status: entry["status"].to_sym, duration: entry["duration"],
        killing_test: entry["killing_test"], test_command: entry["test_command"] }
    end

    def store(mutation, result_data)
      file_key = file_key(mutation)
      entry_key = entry_key(mutation)
      data = read_file(file_key) || {}

      data[entry_key] = {
        "status" => result_data[:status].to_s,
        "duration" => result_data[:duration],
        "killing_test" => result_data[:killing_test],
        "test_command" => result_data[:test_command]
      }

      write_file(file_key, data)
    end

    def clear
      FileUtils.rm_rf(@cache_dir)
    end

    private

    def file_key(mutation)
      content_hash = Digest::SHA256.hexdigest(mutation.original_source)
      "#{safe_filename(mutation.file_path)}_#{content_hash[0, 16]}"
    end

    def entry_key(mutation)
      "#{mutation.operator_name}:#{mutation.line}:#{mutation.column}"
    end

    def safe_filename(path)
      path.gsub(%r{[/\\]}, "_").gsub(/[^a-zA-Z0-9._-]/, "")
    end

    def read_file(file_key)
      path = cache_path(file_key)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    def write_file(file_key, data)
      FileUtils.mkdir_p(@cache_dir)
      path = cache_path(file_key)
      tmp = "#{path}.#{Process.pid}.tmp"
      File.write(tmp, JSON.generate(data))
      File.rename(tmp, path)
    end

    def cache_path(file_key)
      File.join(@cache_dir, "#{file_key}.json")
    end
  end
end
