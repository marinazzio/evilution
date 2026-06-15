# frozen_string_literal: true

require "digest"
require_relative "../coverage"

# Stable, content-addressed digest of a source file, used by MapStore to detect
# when a cached coverage entry has gone stale. Path-independent: the digest
# depends only on the bytes, so moving a file does not invalidate it. Returns
# nil for a missing file so callers treat it as "not fresh".
class Evilution::Coverage::Digest
  def for_file(path)
    return nil unless File.file?(path)

    ::Digest::SHA256.hexdigest(File.binread(path))
  end
end
