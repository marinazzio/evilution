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

    context "with a spec_selector" do
      let(:selector) { instance_double(Evilution::SpecSelector) }
      let(:selector_baseline) do
        described_class.new(spec_resolver: spec_resolver, spec_selector: selector, timeout: 5)
      end

      it "runs the resolved specs of every subject" do
        allow(selector).to receive(:call).with("lib/user.rb").and_return(["spec/user_spec.rb"])
        allow(selector).to receive(:call).with("lib/order.rb").and_return(["spec/order_spec.rb"])
        allow(selector_baseline).to receive(:run_spec_file).and_return(true)

        selector_baseline.call([subject1, subject3])

        expect(selector_baseline).to have_received(:run_spec_file).with("spec/user_spec.rb")
        expect(selector_baseline).to have_received(:run_spec_file).with("spec/order_spec.rb")
      end

      it "runs every spec file the selector returns" do
        allow(selector).to receive(:call).with("lib/user.rb")
                                         .and_return(["spec/user_spec.rb", "spec/user_edge_spec.rb"])
        allow(selector_baseline).to receive(:run_spec_file).and_return(true)

        selector_baseline.call([subject1])

        expect(selector_baseline).to have_received(:run_spec_file).with("spec/user_spec.rb")
        expect(selector_baseline).to have_received(:run_spec_file).with("spec/user_edge_spec.rb")
      end

      it "treats a nil selection as unresolved" do
        allow(selector).to receive(:call).with("lib/user.rb").and_return(nil)
        allow(spec_resolver).to receive(:suggest).with("lib/user.rb").and_return(nil)
        allow(selector_baseline).to receive(:run_spec_file).with("spec").and_return(true)

        expect { selector_baseline.call([subject1]) }.to output(/No matching test found/).to_stderr
        expect(selector_baseline).to have_received(:run_spec_file).with("spec")
      end
    end

    context "with fallback_to_full_suite: false" do
      let(:strict_baseline) do
        described_class.new(spec_resolver: spec_resolver, timeout: 5, fallback_dir: "test",
                            fallback_to_full_suite: false)
      end

      before do
        allow(spec_resolver).to receive(:call).with("lib/user.rb").and_return(nil)
        allow(spec_resolver).to receive(:suggest).with("lib/user.rb").and_return(nil)
      end

      it "does not run the fallback directory for an unresolved source" do
        allow(strict_baseline).to receive(:run_spec_file).and_return(true)

        result = strict_baseline.call([subject1, subject3])

        expect(strict_baseline).to have_received(:run_spec_file).once
        expect(strict_baseline).to have_received(:run_spec_file).with("spec/order_spec.rb")
        expect(result.failed_spec_files).to be_empty
      end

      it "warns for each distinct unresolved source file" do
        allow(spec_resolver).to receive(:call).with("lib/order.rb").and_return(nil)
        allow(spec_resolver).to receive(:suggest).with("lib/order.rb").and_return(nil)
        allow(strict_baseline).to receive(:run_spec_file).and_return(true)

        expect { strict_baseline.call([subject1, subject3]) }
          .to output(%r{lib/user\.rb.*\n.*lib/order\.rb}).to_stderr
      end

      it "warns once per unresolved source file" do
        allow(strict_baseline).to receive(:run_spec_file).and_return(true)

        expect { strict_baseline.call([subject1, subject2]) }
          .to output(%r{\A[^\n]*No matching test found for lib/user\.rb[^\n]*\n\z}).to_stderr
      end

      it "says the source's mutations will be unresolved, not that the full suite runs" do
        allow(strict_baseline).to receive(:run_spec_file).and_return(true)

        expected = "No matching test found for lib/user.rb, marking its mutations unresolved. " \
                   "Use --spec to specify the test file, or --fallback-full-suite to run the whole suite."

        expect { strict_baseline.call([subject1]) }.to output(/#{Regexp.escape(expected)}/).to_stderr
      end

      it "keeps the best-guess hint" do
        allow(spec_resolver).to receive(:suggest).with("lib/user.rb").and_return("test/models/user_test.rb")
        allow(strict_baseline).to receive(:run_spec_file).and_return(true)

        expect { strict_baseline.call([subject1]) }
          .to output(%r{marking its mutations unresolved\. Pass --spec test/models/user_test\.rb \(best guess\)})
          .to_stderr
      end
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

    # a baseline killed by the timeout still counts as failing, but
    # must say so instead of silently recording a failure.
    # Drives read_result directly with a child that never reports back: going
    # through fork_spec_runner would reopen the child's stderr, which clashes
    # with RSpec's stderr capture.
    it "reports a baseline that timed out and treats it as failing" do
      slow_baseline = described_class.new(spec_resolver: spec_resolver, timeout: 0.2)
      read_io, write_io = IO.pipe
      pid = Process.spawn(RbConfig.ruby, "-e", "sleep 5")
      passed = :unset

      begin
        expect { passed = slow_baseline.read_result(read_io, pid, "spec/user_spec.rb") }
          .to output(%r{Baseline for spec/user_spec\.rb timed out after 0\.2s; treating it as failing}).to_stderr
      ensure
        read_io.close
        write_io.close
      end
      expect(passed).to be(false)
    end

    # The stand-in child keeps a copy of the pipe's write end open, as a real
    # hung child would, so the parent waits out the timeout instead of EOF.
    it "names the spec file in the timeout report when run through run_spec_file" do
      slow_baseline = described_class.new(spec_resolver: spec_resolver, timeout: 0.2, runner: ->(_f) {})
      held_write_end = nil
      allow(slow_baseline).to receive(:fork_spec_runner) do |_spec_file, _read_io, write_io|
        held_write_end = write_io.dup
        Process.spawn(RbConfig.ruby, "-e", "sleep 5")
      end

      expect { slow_baseline.run_spec_file("spec/user_spec.rb") }
        .to output(%r{Baseline for spec/user_spec\.rb timed out}).to_stderr
    ensure
      held_write_end.close if held_write_end
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
