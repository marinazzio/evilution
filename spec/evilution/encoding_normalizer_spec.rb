# frozen_string_literal: true

require "json"
require "evilution/encoding_normalizer"

RSpec.describe Evilution::EncodingNormalizer do
  subject(:normalizer) { described_class.new }

  # Valid UTF-8 bytes tagged as BINARY, the way subprocess output and file reads
  # in binary mode arrive.
  let(:binary_utf8) { "あ".b }

  it "exposes only #call" do
    expect(described_class.public_instance_methods(false)).to eq([:call])
  end

  describe "#call" do
    context "with a binary string holding valid UTF-8" do
      it "retags it UTF-8 keeping the bytes" do
        normalized = normalizer.call(binary_utf8)

        expect(normalized).to eq("あ")
        expect(normalized.encoding).to eq(Encoding::UTF_8)
        expect(normalized.bytes).to eq(binary_utf8.bytes)
      end

      it "leaves the input string binary" do
        normalizer.call(binary_utf8)

        expect(binary_utf8.encoding).to eq(Encoding::BINARY)
      end

      it "copes with a frozen input" do
        frozen = binary_utf8.freeze

        expect(normalizer.call(frozen)).to eq("あ")
        expect(frozen.encoding).to eq(Encoding::BINARY)
      end
    end

    context "with a binary string holding invalid UTF-8" do
      it "replaces each invalid byte with the replacement character" do
        normalized = normalizer.call("ok \xFF\xFE end".b)

        expect(normalized).to eq("ok \u{FFFD}\u{FFFD} end")
        expect(normalized.encoding).to eq(Encoding::UTF_8)
        expect(normalized).to be_valid_encoding
      end
    end

    context "with an ASCII-only binary string" do
      it "retags it UTF-8" do
        normalized = normalizer.call("plain".b)

        expect(normalized).to eq("plain")
        expect(normalized.encoding).to eq(Encoding::UTF_8)
      end
    end

    context "with a UTF-8 string holding invalid bytes" do
      let(:invalid_utf8) { (+"bad \xFF\xFE end").force_encoding(Encoding::UTF_8) }

      it "returns a copy with each invalid byte replaced by the replacement character" do
        normalized = normalizer.call(invalid_utf8)

        expect(normalized).to eq("bad \u{FFFD}\u{FFFD} end")
        expect(normalized.encoding).to eq(Encoding::UTF_8)
        expect(normalized).to be_valid_encoding
        expect(normalized).not_to equal(invalid_utf8)
      end

      it "leaves the input string unchanged" do
        bytes = invalid_utf8.bytes

        normalizer.call(invalid_utf8)

        expect(invalid_utf8.bytes).to eq(bytes)
        expect(invalid_utf8.encoding).to eq(Encoding::UTF_8)
        expect(invalid_utf8).not_to be_valid_encoding
      end

      it "copes with a frozen input" do
        frozen = invalid_utf8.freeze

        expect(normalizer.call(frozen)).to eq("bad \u{FFFD}\u{FFFD} end")
      end

      it "produces a string JSON.generate accepts" do
        expect(JSON.parse(JSON.generate([normalizer.call(invalid_utf8)]))).to eq(["bad \u{FFFD}\u{FFFD} end"])
      end
    end

    context "with a string neither binary nor invalid UTF-8" do
      it "returns the very same UTF-8 string" do
        string = "déjà vu"

        expect(normalizer.call(string)).to equal(string)
      end

      it "leaves a string in another encoding as it is" do
        string = "déjà".encode(Encoding::ISO_8859_1)

        expect(normalizer.call(string)).to equal(string)
      end

      it "leaves a UTF-16LE string as it is" do
        string = "déjà".encode(Encoding::UTF_16LE)

        expect(normalizer.call(string)).to equal(string)
      end
    end

    context "with non-string scalars" do
      it "returns them untouched" do
        scalars = [1, 1.5, nil, true, false, :sym]

        expect(scalars.map { |s| normalizer.call(s) }).to eq(scalars)
      end
    end

    context "with nested collections" do
      let(:payload) do
        {
          summary: { total: 1 },
          killed: [{ diff: binary_utf8, line: 3, extras: ["x".b, [binary_utf8]] }],
          binary_utf8 => "value",
          "plain" => binary_utf8
        }
      end

      it "normalizes strings in hash values, arrays and hash keys at any depth" do
        expect(normalizer.call(payload)).to eq(
          summary: { total: 1 },
          killed: [{ diff: "あ", line: 3, extras: ["x", ["あ"]] }],
          "あ" => "value",
          "plain" => "あ"
        )
      end

      it "retags every nested string UTF-8" do
        normalized = normalizer.call(payload)
        killed = normalized[:killed].first

        expect(killed[:diff].encoding).to eq(Encoding::UTF_8)
        expect(killed[:extras].flatten.map(&:encoding)).to eq([Encoding::UTF_8, Encoding::UTF_8])
        expect(normalized.keys.grep(String).map(&:encoding)).to eq([Encoding::UTF_8, Encoding::UTF_8])
      end

      it "leaves the input payload binary" do
        normalizer.call(payload)

        expect(payload[:killed].first[:diff].encoding).to eq(Encoding::BINARY)
        expect(payload["plain"].encoding).to eq(Encoding::BINARY)
      end

      it "produces a payload JSON.generate accepts" do
        expect(JSON.parse(JSON.generate(normalizer.call(payload)))["killed"].first["diff"]).to eq("あ")
      end
    end

    context "with a binary key and a UTF-8 key that hold the same text" do
      it "keeps one key, with the value of the later entry" do
        expect(normalizer.call({ "あ" => "first", binary_utf8 => "second" })).to eq("あ" => "second")
        expect(normalizer.call({ binary_utf8 => "first", "あ" => "second" })).to eq("あ" => "second")
      end
    end
  end
end
