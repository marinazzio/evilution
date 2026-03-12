# frozen_string_literal: true

require "tempfile"

RSpec.describe Evilution::Isolation::Fork do
  subject(:isolator) { described_class.new }

  let(:tmpfile) { Tempfile.new("fork_spec") }
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

  describe "#call" do
    it "returns killed when test command fails" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_killed
      expect(result.mutation).to eq(mutation)
    end

    it "returns survived when test command passes" do
      test_command = ->(_m) { { passed: true } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_survived
    end

    it "returns timeout when child exceeds time limit" do
      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

      expect(result).to be_timeout
    end

    it "restores the original file after a timeout" do
      test_command = lambda { |m|
        File.write(m.file_path, "mutated content")
        sleep 10
        { passed: true }
      }

      isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

      expect(File.read(tmpfile.path)).to eq(original_content)
    end

    it "returns error when test command raises" do
      test_command = ->(_m) { raise "boom" }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_error
    end

    it "records duration" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.duration).to be > 0
    end

    it "isolates mutations from parent process" do
      parent_value = "original"
      test_command = lambda do |_m|
        parent_value = "mutated_in_child"
        { passed: false }
      end

      isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(parent_value).to eq("original")
    end
  end
end
