# frozen_string_literal: true

require "digest"
require_relative "../cache"

# A digest of the contents of a set of test files. A directory stands for the
# Ruby files under it, and a path with no file behind it digests as missing,
# so a file appearing or going away changes the digest too.
#
# Each file is read once for the life of the instance, which belongs to one
# run: the same spec files resolve for every subject of a source file.
class Evilution::Cache::SpecDigest
  MISSING = "missing"
  private_constant :MISSING

  def initialize
    @files = {}
  end

  # nil when there are no paths: there is nothing to vouch for the verdict.
  def call(paths)
    expanded = Array(paths).flat_map { |path| expand(path.to_s) }.uniq.sort
    return nil if expanded.empty?

    Digest::SHA256.hexdigest(expanded.map { |path| "#{path}\0#{file_digest(path)}" }.join("\n"))
  end

  private

  def expand(path)
    return [path] unless File.directory?(path)

    Dir.glob(File.join(path, "**", "*.rb"))
  end

  def file_digest(path)
    @files[path] ||= File.file?(path) ? Digest::SHA256.hexdigest(File.binread(path)) : MISSING
  end
end
