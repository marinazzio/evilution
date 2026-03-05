# frozen_string_literal: true

require "tempfile"

RSpec.describe Evilution::Coverage::Collector do
  subject(:collector) { described_class.new }

  describe "#call" do
    it "returns a Hash" do
      result = collector.call(test_files: [])

      expect(result).to be_a(Hash)
    end

    it "returns coverage data keyed by absolute file paths" do
      source = Tempfile.new(["source", ".rb"])
      source.write("def _cov_test_keyed; 42; end\n")
      source.flush

      spec_file = Tempfile.new(["spec", "_spec.rb"])
      spec_file.write(<<~RUBY)
        require "#{source.path}"
        RSpec.describe "_cov_test_keyed" do
          it("works") { expect(_cov_test_keyed).to eq(42) }
        end
      RUBY
      spec_file.flush

      result = collector.call(test_files: [spec_file.path])

      expect(result.keys).to all(be_a(String))
      expect(result[source.path]).to be_a(Array)
    ensure
      source&.close!
      spec_file&.close!
    end

    it "records line-level hit counts for code exercised by specs" do
      source = Tempfile.new(["source", ".rb"])
      source.write("def _cov_test_hits; 99; end\n")
      source.flush

      spec_file = Tempfile.new(["spec", "_spec.rb"])
      spec_file.write(<<~RUBY)
        require "#{source.path}"
        RSpec.describe "_cov_test_hits" do
          it("calls the method") { expect(_cov_test_hits).to eq(99) }
        end
      RUBY
      spec_file.flush

      result = collector.call(test_files: [spec_file.path])

      line_data = result[source.path]
      expect(line_data).to be_a(Array)
      # The single executable line should have been hit
      expect(line_data.compact.first).to be >= 1
    ensure
      source&.close!
      spec_file&.close!
    end

    it "returns an empty hash when no test files are given" do
      result = collector.call(test_files: [])

      expect(result).to eq({})
    end

    it "isolates coverage collection from the parent process" do
      source = Tempfile.new(["source", ".rb"])
      source.write("def _cov_test_iso; 2; end\n")
      source.flush

      spec_file = Tempfile.new(["spec", "_spec.rb"])
      spec_file.write(<<~RUBY)
        require "#{source.path}"
        RSpec.describe "_cov_test_iso" do
          it("works") { expect(_cov_test_iso).to eq(2) }
        end
      RUBY
      spec_file.flush

      collector.call(test_files: [spec_file.path])

      # Coverage should not be running in the parent process after the call
      expect(Coverage.running?).to be false
    ensure
      source&.close!
      spec_file&.close!
    end
  end
end
