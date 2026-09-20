# frozen_string_literal: true

RSpec.describe Evilution::Reporter::CLI::LineFormatters::UnresolvedTargets do
  subject(:formatter) { described_class.new }

  # Summary freezes the list it carries, so the double hands out a frozen one
  # too — a formatter that mutated it in place would raise in a real run.
  def summary_with(unresolved_target_files, target_file_count: 2)
    instance_double(
      Evilution::Result::Summary,
      unresolved_target_files: unresolved_target_files.freeze,
      unresolved_targets?: !unresolved_target_files.empty?,
      target_file_count: target_file_count
    )
  end

  describe "#format" do
    it "returns nil when every target file resolved" do
      expect(formatter.format(summary_with([]))).to be_nil
    end

    it "names the one file that resolved to no spec" do
      expect(formatter.format(summary_with(["lib/untested.rb"]))).to eq(
        "! 1 of 2 target files has no resolvable spec — it was never tested:\n    " \
        "lib/untested.rb"
      )
    end

    it "names every unresolved file" do
      files = ["app/services/a.rb", "app/services/b.rb"]

      expect(formatter.format(summary_with(files, target_file_count: 5))).to eq(
        "! 2 of 5 target files have no resolvable spec — they were never tested:\n    " \
        "app/services/a.rb\n    " \
        "app/services/b.rb"
      )
    end

    # The count is unknown when the summary predates it (a saved session, say),
    # so the line drops the ratio rather than inventing one.
    it "omits the ratio when the target count is unknown" do
      expect(formatter.format(summary_with(["lib/untested.rb"], target_file_count: nil))).to eq(
        "! 1 target file has no resolvable spec — it was never tested:\n    " \
        "lib/untested.rb"
      )
    end
  end
end
