# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"

# The verdicts --incremental keeps across runs, one JSON file per source file:
#
#   { "format": 2, "path": "lib/shop.rb",
#     "subjects": { <subject key>: { "name": "Shop#price",
#                                    "mutations": { <mutation key>: { "status": ..., ... } } } } }
#
# What the keys stand for is up to Cache::Keys. A file is read once per run,
# when its first mutation is looked up, and verdicts are stored in memory
# and written a file at a time: when the run moves on to the next source
# file, and at #flush. Storing a verdict therefore costs the same however
# many the file already holds.
#
# Writing a file drops what it holds for an earlier version of a subject the
# run just looked up, and for a subject the file no longer has, so a file
# holds roughly one version of each subject.
class Evilution::Cache
  DEFAULT_DIR = "tmp/evilution_cache"
  FORMAT = 2
  FORMAT_DIR = "v#{FORMAT}".freeze

  autoload :Keys, File.expand_path("cache/keys", __dir__)
  autoload :RunFingerprint, File.expand_path("cache/run_fingerprint", __dir__)
  autoload :Skeleton, File.expand_path("cache/skeleton", __dir__)
  autoload :SpecDigest, File.expand_path("cache/spec_digest", __dir__)

  def initialize(keys:, cache_dir: DEFAULT_DIR)
    @keys = keys
    @cache_dir = cache_dir
    @owner = Process.pid
    reset
  end

  # Every subject parsed from the run's files (see Cache::Keys#index).
  def index(subjects)
    @keys.index(subjects)
  end

  def fetch(mutation)
    keys = keys_for(mutation)
    return nil unless keys

    subject_key, mutation_key = keys
    file_path = mutation.file_path
    touch(file_path, subject_key, mutation.subject.name)
    entry = subjects_of(file_path)[subject_key]
    return nil unless entry

    from_entry(entry["mutations"][mutation_key])
  end

  def store(mutation, result_data)
    keys = keys_for(mutation)
    return unless keys

    subject_key, mutation_key = keys
    file_path = mutation.file_path
    move_to(file_path)
    name = mutation.subject.name
    touch(file_path, subject_key, name)
    entry = subjects_of(file_path)[subject_key] ||= { "name" => name, "mutations" => {} }
    entry["mutations"][mutation_key] = to_entry(result_data)
    @dirty[file_path] = true
  end

  # Writes every file stored to since it was last written. Only the process
  # that made the cache writes: a forked child holds a copy of its verdicts.
  def flush
    return unless Process.pid == @owner

    @dirty.each_key { |file_path| write(file_path) }
    @dirty.clear
    remove_earlier_format
  end

  def clear
    FileUtils.rm_rf(@cache_dir)
    reset
  end

  private

  def reset
    @files = {}
    @dirty = {}
    @touched = Hash.new { |hash, file_path| hash[file_path] = {} }
    @current = nil
  end

  # [subject key, mutation key], or nil when either is missing.
  def keys_for(mutation)
    subject_key = @keys.subject_key(mutation)
    mutation_key = subject_key && @keys.mutation_key(mutation)
    mutation_key && [subject_key, mutation_key]
  end

  def touch(file_path, subject_key, name)
    @touched[file_path][subject_key] = name
  end

  # Mutations come file by file, so a file is done once the next one starts;
  # writing it then keeps what a run that is cut short had already judged.
  def move_to(file_path)
    previous = @current
    @current = file_path
    return if previous == file_path || !@dirty.delete(previous)

    write(previous) if Process.pid == @owner
  end

  def to_entry(data)
    {
      "status" => data[:status].to_s,
      "duration" => data[:duration],
      "killing_test" => data[:killing_test],
      "test_command" => data[:test_command],
      "time_limit" => data[:time_limit]
    }
  end

  # The reports round the duration and time limit, so an entry whose
  # duration is not a number is no entry, and such a time limit is none.
  def from_entry(entry)
    return nil unless entry.is_a?(Hash) && entry["status"].is_a?(String) && entry["duration"].is_a?(Numeric)

    time_limit = entry["time_limit"]
    { status: entry["status"].to_sym, duration: entry["duration"], killing_test: entry["killing_test"],
      test_command: entry["test_command"], time_limit: time_limit.is_a?(Numeric) ? time_limit : nil }
  end

  def subjects_of(file_path)
    @files[file_path] ||= read(file_path)
  end

  # What a file holds, with anything not of the expected shape left out. A
  # source file with no cache file yet holds nothing.
  def read(file_path)
    data = JSON.parse(File.read(cache_path(file_path)))
    return {} unless data.is_a?(Hash) && data["format"] == FORMAT && data["subjects"].is_a?(Hash)

    data["subjects"].select { |_key, entry| entry.is_a?(Hash) && entry["mutations"].is_a?(Hash) }
  rescue JSON::ParserError, SystemCallError
    {}
  end

  def write(file_path)
    subjects = current_subjects(file_path)
    path = cache_path(file_path)
    FileUtils.mkdir_p(File.dirname(path))
    tmp = "#{path}.#{Process.pid}.tmp"
    File.write(tmp, JSON.generate("format" => FORMAT, "path" => file_path, "subjects" => subjects))
    File.rename(tmp, path)
  end

  # A subject's entry stays when the run looked it up, or when the run
  # neither looked up another version of it nor found the file without it.
  def current_subjects(file_path)
    touched = @touched[file_path]
    touched_names = touched.values
    known = @keys.subject_names(file_path)
    subjects_of(file_path).select do |subject_key, entry|
      next true if touched.key?(subject_key)

      name = entry["name"]
      !touched_names.include?(name) && (known.nil? || known.include?(name))
    end
  end

  # The cache files of format 1 sat directly in the cache directory, one per
  # version of a source file, and are never read again.
  def remove_earlier_format
    FileUtils.rm_f(Dir.glob(File.join(@cache_dir, "*.json")))
  end

  def cache_path(file_path)
    name = "#{safe_filename(file_path)}-#{Digest::SHA256.hexdigest(file_path)[0, 12]}.json"
    File.join(@cache_dir, FORMAT_DIR, name)
  end

  def safe_filename(path)
    path.gsub(%r{[/\\]}, "_").gsub(/[^a-zA-Z0-9._-]/, "")
  end
end
