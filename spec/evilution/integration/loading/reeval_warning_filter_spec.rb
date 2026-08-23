# frozen_string_literal: true

require "evilution/integration/loading/reeval_warning_filter"

# The `warning` gem installs its handler with Warning.extend, which lands BEHIND
# anything prepended to Warning's singleton -- exactly the ordering the filter
# relies on. An RSpec stub prepends its own module instead, so it would sit
# AHEAD of the filter and exercise the wrong arrangement.
module SpecWarningHandler
  ACTIVE_KEY = :__ev_spec_raise_on_warning

  def warn(message, *args, **kwargs)
    raise "promoted: #{message.to_s.strip}" if Thread.current[ACTIVE_KEY]

    super
  end
end
Warning.extend(SpecWarningHandler)

RSpec.describe Evilution::Integration::Loading::ReevalWarningFilter do
  # Mirrors dry-schema: `.rspec` sets --warnings ($VERBOSE = true, the only
  # mode in which Ruby emits redefinition warnings) and spec_helper installs
  # Warning.process { |w| raise w }. Both halves are needed to reproduce.
  around do |example|
    previous = $VERBOSE
    $VERBOSE = true
    example.run
  ensure
    $VERBOSE = previous
    Object.send(:remove_const, :EvFilterTarget) if defined?(EvFilterTarget)
  end

  # The `warning` gem installs its handler with Warning.extend, which lands
  # BEHIND anything prepended to Warning's singleton -- exactly the ordering the
  # filter relies on. An RSpec stub prepends its own module instead, so it would
  # sit ahead of the filter and test the wrong arrangement.
  def with_raising_handler
    Thread.current[SpecWarningHandler::ACTIVE_KEY] = true
    yield
  ensure
    Thread.current[SpecWarningHandler::ACTIVE_KEY] = nil
  end

  def redefine_twice
    source = "class EvFilterTarget\n  def value\n    1\n  end\nend\n"
    2.times { eval(source, TOPLEVEL_BINDING, "ev_filter_target.rb", 1) } # rubocop:disable Security/Eval
  end

  describe ".suppress" do
    it "drops the redefinition warnings that re-evaluating a file always produces" do
      described_class.install

      expect { described_class.suppress { redefine_twice } }
        .not_to output(/method redefined/).to_stderr
    end

    it "keeps a raising handler from seeing those warnings" do
      with_raising_handler do
        expect { described_class.suppress { redefine_twice } }.not_to raise_error
      end
    end

    # The blunt $VERBOSE = nil approach swallowed these too, which costs a kill:
    # a mutation that introduces a warning would go unnoticed under a handler
    # that would otherwise raise on it.
    it "still lets an unrelated warning reach the handler" do
      described_class.install

      expect do
        described_class.suppress do
          eval("def ev_unused_probe(a)\n  b = 1\n  a\nend\n", TOPLEVEL_BINDING, __FILE__, __LINE__)
        end
      end.to output(/assigned but unused variable/).to_stderr
    end

    # The other cost of $VERBOSE = nil: the evaluated file saw a different
    # $VERBOSE than a normal load would, so load-time code branching on it took
    # the wrong path.
    it "leaves $VERBOSE alone so evaluated code sees the caller's value" do
      described_class.suppress do
        expect($VERBOSE).to be(true)
      end
    end

    it "does not filter outside the suppression window" do
      described_class.install

      expect { redefine_twice }.to output(/method redefined/).to_stderr
    end

    it "installs the filter before running the block" do
      expect(described_class).to receive(:install).and_call_original

      described_class.suppress { nil }
    end

    it "reports inactive as false rather than merely falsy" do
      expect(described_class.active?).to be(false)
    end

    it "passes a warning category through to the handler" do
      described_class.install
      seen = []
      allow(Warning).to receive(:warn).and_wrap_original do |_orig, _message, **kwargs|
        seen << kwargs[:category]
        nil
      end

      described_class.suppress { Warning.warn("some other warning", category: :deprecated) }

      expect(seen).to eq([:deprecated])
    end

    it "clears the window even when the block raises" do
      expect { described_class.suppress { raise "boom" } }.to raise_error("boom")
      expect(described_class).not_to be_active
    end

    it "restores a nested window rather than clearing it wholesale" do
      described_class.suppress do
        described_class.suppress { nil }
        expect(described_class).to be_active
      end
    end
  end

  describe ".mechanism_warning?" do
    it "matches the three shapes re-eval produces" do
      expect(described_class).to be_mechanism_warning("warning: method redefined; discarding old value")
      expect(described_class).to be_mechanism_warning("warning: already initialized constant FOO")
      expect(described_class).to be_mechanism_warning("warning: previous definition of value was here")
    end

    it "does not match warnings that come from the code itself" do
      expect(described_class).not_to be_mechanism_warning("warning: assigned but unused variable - b")
    end
  end

  describe ".install" do
    it "prepends the filter to the target" do
      target = Module.new

      described_class.install(target)

      expect(target.ancestors).to include(described_class::Filter)
    end

    it "is idempotent, so a warning is never filtered twice" do
      target = Module.new

      2.times { described_class.install(target) }

      expect(target.ancestors.count(described_class::Filter)).to eq(1)
    end

    it "installs into Warning's singleton by default" do
      described_class.install

      expect(Warning.singleton_class.ancestors).to include(described_class::Filter)
    end
  end
end
