# frozen_string_literal: true

require "digest"
require_relative "../compare"

# Composes a stable SHA256 fingerprint from a mutation diff for cross-tool
# matching (Evilution vs Mutant). Orchestrates two collaborators along
# distinct change axes:
#
#   - extractor: parses a tool-specific diff format into {minus:, plus:}
#   - normalizer: collapses whitespace per line so cosmetic differences
#                 don't perturb the hash
class Evilution::Compare::Fingerprint
  def initialize(extractor:, normalizer:)
    @extractor = extractor
    @normalizer = normalizer
  end

  def call(diff:, file_path:, line:)
    body = @extractor.call(diff)
    minus = body[:minus].map { |l| @normalizer.call(l) }
    plus  = body[:plus].map  { |l| @normalizer.call(l) }
    payload = [file_path, line.to_s, minus.join("\n"), plus.join("\n")].join("\x00")
    Digest::SHA256.hexdigest(payload)
  end
end
