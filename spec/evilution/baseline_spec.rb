# frozen_string_literal: true

require "evilution/baseline"

RSpec.describe Evilution::Baseline do
  let(:spec_resolver) { instance_double(Evilution::SpecResolver) }

  subject(:baseline) { described_class.new(spec_resolver: spec_resolver, timeout: 5) }

  describe "#call" do
    let(:subject1) { double("Subject1", file_path: "lib/user.rb") }
    let(:subject2) { double("Subject2", file_path: "lib/user.rb") }
    let(:subject3) { double("Subject3", file_path: "lib/order.rb") }

    before do
      allow(spec_resolver).to receive(:call).with("lib/user.rb").and_return("spec/user_spec.rb")
      allow(spec_resolver).to receive(:call).with("lib/order.rb").and_return("spec/order_spec.rb")
    end

    it "returns a result with failed spec files" do
      allow(baseline).to receive(:run_spec_file).with("spec/user_spec.rb").and_return(false)
      allow(baseline).to receive(:run_spec_file).with("spec/order_spec.rb").and_return(true)

      result = baseline.call([subject1, subject2, subject3])

      expect(result.failed_spec_files).to contain_exactly("spec/user_spec.rb")
    end

    it "deduplicates spec files from multiple subjects" do
      allow(baseline).to receive(:run_spec_file).with("spec/user_spec.rb").and_return(true)
      allow(baseline).to receive(:run_spec_file).with("spec/order_spec.rb").and_return(true)

      baseline.call([subject1, subject2, subject3])

      expect(baseline).to have_received(:run_spec_file).with("spec/user_spec.rb").once
    end

    it "returns empty set when all specs pass" do
      allow(baseline).to receive(:run_spec_file).and_return(true)

      result = baseline.call([subject1, subject3])

      expect(result.failed_spec_files).to be_empty
    end

    it "returns empty result for empty subjects list" do
      result = baseline.call([])

      expect(result.failed_spec_files).to be_empty
    end

    it "treats unresolvable spec files as fallback directory" do
      allow(spec_resolver).to receive(:call).with("lib/user.rb").and_return(nil)
      allow(spec_resolver).to receive(:suggest).with("lib/user.rb").and_return(nil)
      allow(baseline).to receive(:run_spec_file).with("spec").and_return(false)

      result = baseline.call([subject1])

      expect(result.failed_spec_files).to contain_exactly("spec")
    end

    it "uses custom fallback_dir when configured" do
      minitest_baseline = described_class.new(
        spec_resolver: spec_resolver, timeout: 5, fallback_dir: "test"
      )
      allow(spec_resolver).to receive(:call).with("lib/user.rb").and_return(nil)
      allow(spec_resolver).to receive(:suggest).with("lib/user.rb").and_return(nil)
      allow(minitest_baseline).to receive(:run_spec_file).with("test").and_return(false)

      result = minitest_baseline.call([subject1])

      expect(result.failed_spec_files).to contain_exactly("test")
    end

    it "warns when falling back to full test suite" do
      allow(spec_resolver).to receive(:call).with("lib/user.rb").and_return(nil)
      allow(spec_resolver).to receive(:suggest).with("lib/user.rb").and_return(nil)
      allow(baseline).to receive(:run_spec_file).with("spec").and_return(true)

      expect { baseline.call([subject1]) }
        .to output(
          %r{No matching test found for lib/user\.rb, running full suite\. Use --spec to specify the test file\.}
        ).to_stderr
    end

    # EV-z7f5 / GH #1325 opt 2: name a likely candidate in the hint when one
    # is found by basename so the user has a file to pass to --spec.
    it "names a suggested candidate in the fallback warning when one is found" do
      allow(spec_resolver).to receive(:call).with("lib/user.rb").and_return(nil)
      allow(spec_resolver).to receive(:suggest).with("lib/user.rb")
                                               .and_return("spec/unit/user_spec.rb")
      allow(baseline).to receive(:run_spec_file).with("spec").and_return(true)

      expect { baseline.call([subject1]) }
        .to output(
          %r{No matching test found for lib/user\.rb, running full suite\. Pass --spec spec/unit/user_spec\.rb \(best guess\)}
        ).to_stderr
    end

    context "with explicit test_files (from --spec flag)" do
      # When the user passes --spec, they have told us which spec files cover
      # the subjects. Baseline must run those spec files (and ONLY those) —
      # never auto-discover or fall back to the full suite. Doing otherwise
      # produces the misleading "No matching test found... Use --spec" warning
      # users have reported even though they did pass --spec, and causes
      # baseline to run unrelated specs that may fail for environment reasons,
      # cascading into wrong score reporting.
      subject(:baseline) do
        described_class.new(
          spec_resolver: spec_resolver, timeout: 5,
          test_files: ["spec/explicit_spec.rb"]
        )
      end

      it "runs the explicit spec files and skips auto-discovery" do
        allow(baseline).to receive(:run_spec_file).with("spec/explicit_spec.rb").and_return(true)

        baseline.call([subject1, subject3])

        expect(baseline).to have_received(:run_spec_file).with("spec/explicit_spec.rb").once
        expect(baseline).not_to have_received(:run_spec_file).with("spec/user_spec.rb")
        expect(baseline).not_to have_received(:run_spec_file).with("spec/order_spec.rb")
      end

      it "does not fire the 'No matching test found' warning when test_files is provided" do
        allow(baseline).to receive(:run_spec_file).with("spec/explicit_spec.rb").and_return(true)

        expect { baseline.call([subject1]) }
          .not_to output(/no matching test/i).to_stderr
      end

      it "reports failed explicit spec files" do
        allow(baseline).to receive(:run_spec_file).with("spec/explicit_spec.rb").and_return(false)

        result = baseline.call([subject1])

        expect(result.failed_spec_files).to contain_exactly("spec/explicit_spec.rb")
      end
    end

    it "records duration" do
      allow(baseline).to receive(:run_spec_file).and_return(true)

      result = baseline.call([subject1])

      expect(result.duration).to be >= 0
    end
  end

  describe "runner callable" do
    it "delegates to the runner proc in fork_spec_runner" do
      runner = ->(file) { file == "spec/user_spec.rb" }
      custom_baseline = described_class.new(
        spec_resolver: spec_resolver, timeout: 5, runner: runner
      )
      allow(spec_resolver).to receive(:call).with("lib/user.rb").and_return("spec/user_spec.rb")

      result = custom_baseline.call([double("Subject", file_path: "lib/user.rb")])

      expect(result.failed_spec_files).to be_empty
    end

    it "raises when fork_spec_runner called without runner" do
      no_runner = described_class.new(spec_resolver: spec_resolver, timeout: 5)

      expect { no_runner.run_spec_file("spec/foo_spec.rb") }
        .to raise_error(Evilution::Error, /no baseline runner configured/)
    end
  end

  describe Evilution::Baseline::Result do
    it "is frozen" do
      result = described_class.new(failed_spec_files: Set.new, duration: 0.0)

      expect(result).to be_frozen
    end

    it "exposes failed_spec_files" do
      result = described_class.new(failed_spec_files: Set["spec/user_spec.rb"], duration: 1.0)

      expect(result.failed_spec_files).to contain_exactly("spec/user_spec.rb")
    end

    it "exposes duration" do
      result = described_class.new(failed_spec_files: Set.new, duration: 2.5)

      expect(result.duration).to eq(2.5)
    end

    describe "#failed?" do
      it "returns true when there are failed spec files" do
        result = described_class.new(failed_spec_files: Set["spec/user_spec.rb"], duration: 0.0)

        expect(result).to be_failed
      end

      it "returns false when no spec files failed" do
        result = described_class.new(failed_spec_files: Set.new, duration: 0.0)

        expect(result).not_to be_failed
      end
    end
  end
end
