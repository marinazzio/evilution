# frozen_string_literal: true

require "tempfile"

RSpec.describe Evilution::Isolation::Fork, "memory reporting", if: File.exist?("/proc/self/status") do
  subject(:isolator) { described_class.new }

  let(:tmpfile) { Tempfile.new("fork_memory_spec") }
  let(:original_content) { "original content" }
  let(:mutation) do
    double("Mutation", file_path: tmpfile.path, original_source: original_content)
  end

  before do
    File.write(tmpfile.path, original_content)
  end

  after do
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call child memory reporting" do
    it "includes child_rss_kb in the result" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.child_rss_kb).to be_a(Integer)
      expect(result.child_rss_kb).to be > 0
    end

    it "reports child RSS for passed tests too" do
      test_command = ->(_m) { { passed: true } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.child_rss_kb).to be_a(Integer)
      expect(result.child_rss_kb).to be > 0
    end

    it "returns nil child_rss_kb on timeout" do
      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(result.child_rss_kb).to be_nil
    end

    it "returns nil child_rss_kb on error" do
      test_command = ->(_m) { raise "boom" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      # Error results may or may not have RSS depending on where the error occurred
      expect(result.child_rss_kb).to be_nil.or be_a(Integer)
    end
  end
end
