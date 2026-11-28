# frozen_string_literal: true

require_relative "version"

# A copy of a payload that JSON.generate can write. Strings tagged BINARY
# (subprocess output, files read in binary mode) are retagged UTF-8, and
# strings tagged UTF-8 that hold invalid bytes (git output forced to UTF-8, a
# child's error message) are copied; in both, bytes that are not valid UTF-8
# become U+FFFD. Valid UTF-8 strings, strings in any other encoding (the json
# gem transcodes those itself) and everything that is not a string pass through
# as the same object. The input is never changed.
#
# The payload must be built from plain Hash, Array and scalar values: any
# other object (a Struct, a Data, a custom class) passes through as it is, and
# the strings inside it are not normalized.
#
# Known limitation: two hash keys that differ only in encoding, such as a
# BINARY "あ".b and a UTF-8 "あ", normalize to the same key and the later entry
# wins. Report keys are Symbols and file paths, so a report never holds both.
class Evilution::EncodingNormalizer
  def call(payload)
    case payload
    when Hash then payload.to_h { |key, value| [call(key), call(value)] }
    when Array then payload.map { |element| call(element) }
    when String then normalize_string(payload)
    else payload
    end
  end

  private

  # scrub's default replacement in a Unicode encoding is U+FFFD.
  def normalize_string(string)
    case string.encoding
    when Encoding::BINARY then string.dup.force_encoding(Encoding::UTF_8).scrub
    when Encoding::UTF_8 then string.valid_encoding? ? string : string.scrub
    else string
    end
  end
end
