# frozen_string_literal: true

require_relative "../json"

# A copy of a report payload that JSON.generate can write: strings tagged
# BINARY (subprocess output, files read in binary mode) are retagged UTF-8, and
# bytes that are not valid UTF-8 become U+FFFD. Strings in any other encoding,
# and everything that is not a string, pass through as they are.
class Evilution::Reporter::JSON::EncodingNormalizer
  def call(payload)
    case payload
    when Hash then payload.to_h { |key, value| [call(key), call(value)] }
    when Array then payload.map { |element| call(element) }
    when String then normalize_string(payload)
    else payload
    end
  end

  private

  def normalize_string(string)
    return string unless string.encoding == Encoding::BINARY

    # scrub's default replacement in a Unicode encoding is U+FFFD.
    string.dup.force_encoding(Encoding::UTF_8).scrub
  end
end
