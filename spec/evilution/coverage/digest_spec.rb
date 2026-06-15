# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "evilution/coverage/digest"

RSpec.describe Evilution::Coverage::Digest do
  subject(:digest) { described_class.new }

  it "returns a stable 64-char hex digest for the same content" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, "a.rb")
      File.write(file, "puts 1\n")
      expect(digest.for_file(file)).to match(/\A[0-9a-f]{64}\z/)
      expect(digest.for_file(file)).to eq(digest.for_file(file))
    end
  end

  it "changes when the file content changes" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, "a.rb")
      File.write(file, "puts 1\n")
      before = digest.for_file(file)
      File.write(file, "puts 2\n")
      expect(digest.for_file(file)).not_to eq(before)
    end
  end

  it "is content-addressed (same content, different path => same digest)" do
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.rb")
      b = File.join(dir, "b.rb")
      File.write(a, "identical")
      File.write(b, "identical")
      expect(digest.for_file(a)).to eq(digest.for_file(b))
    end
  end

  it "returns nil for a missing file" do
    expect(digest.for_file("/no/such/file.rb")).to be_nil
  end
end
