# frozen_string_literal: true

require "English"

require "evilution/cli/exit_guard"

RSpec.describe Evilution::CLI::ExitGuard do
  subject(:guard) { described_class.new(register: register, exiter: exiter, died: died) }

  let(:hooks) { [] }
  let(:register) { ->(&hook) { hooks << hook } }
  let(:exits) { [] }
  let(:exiter) { ->(status) { exits << status } }
  let(:died) { -> { false } }

  def run_hooks
    hooks.each(&:call)
  end

  describe "#install" do
    it "returns the guard, so a caller can keep hold of it" do
      expect(guard.install).to be(guard)
    end

    it "registers one hook" do
      guard.install

      expect(hooks.length).to eq(1)
    end

    # The guard is installed before the project's preload, so its hook is the
    # last to run and gets the final word on the process status.
    it "exits with the status it was given" do
      guard.install
      guard.status = 1

      run_hooks

      expect(exits).to eq([1])
    end

    it "exits with zero when that is the status" do
      guard.install
      guard.status = 0

      run_hooks

      expect(exits).to eq([0])
    end

    # Nothing set a status, so evilution did not finish normally — an exception
    # is on its way out and Ruby's own handling should decide the status.
    it "stays out of the way when no status was recorded" do
      guard.install

      run_hooks

      expect(exits).to be_empty
    end

    it "does nothing until its hook runs" do
      guard.install
      guard.status = 1

      expect(exits).to be_empty
    end
  end

  # Evilution forks workers, and a fork inherits its parent's at_exit hooks.
  describe "in a forked child" do
    it "stays out of the way" do
      pids = [100, 200]
      guard = described_class.new(register: register, exiter: exiter, pid_source: -> { pids.shift })
      guard.install
      guard.status = 1

      run_hooks

      expect(exits).to be_empty
    end

    it "still exits in the process that installed it" do
      guard = described_class.new(register: register, exiter: exiter, pid_source: -> { 100 })
      guard.install
      guard.status = 1

      run_hooks

      expect(exits).to eq([1])
    end
  end

  # A run under in-process isolation that a mutation took down measured
  # nothing. Ruby would end it with 1, which reads as a score below the
  # minimum; it is a tool error, and the notice on stderr says what to change.
  describe "a run that died under in-process isolation" do
    let(:died) { -> { true } }

    it "exits with the status of a tool error" do
      guard.install

      run_hooks

      expect(exits).to eq([2])
    end

    it "keeps a status that was recorded" do
      guard.install
      guard.status = 0

      run_hooks

      expect(exits).to eq([0])
    end

    it "stays out of the way in a forked child" do
      pids = [100, 200]
      guard = described_class.new(register: register, exiter: exiter, died: died, pid_source: -> { pids.shift })
      guard.install

      run_hooks

      expect(exits).to be_empty
    end

    it "flushes the streams before exiting" do
      stream = double("stream")
      allow(stream).to receive(:flush)
      guard = described_class.new(register: register, exiter: exiter, died: died, streams: -> { [stream] })
      guard.install

      run_hooks

      expect(stream).to have_received(:flush)
    end

    # Unless told otherwise the guard asks in-process isolation itself.
    describe "as in-process isolation reports it" do
      subject(:guard) { described_class.new(register: register, exiter: exiter) }

      let(:in_process) { Evilution::Isolation::InProcess }

      after { in_process.unwatch }

      it "exits with the status of a tool error once a death was reported" do
        in_process.watch(double("Mutation", to_s: "constant_namespace_strip: lib/example.rb:202"))
        in_process.report_death(SystemStackError.new("stack level too deep"), stream: StringIO.new)
        guard.install

        run_hooks

        expect(exits).to eq([2])
      end

      it "stays out of the way when none was" do
        guard.install

        run_hooks

        expect(exits).to be_empty
      end
    end
  end

  # exit! does not flush, so whatever is still buffered would be lost.
  describe "flushing" do
    it "flushes the streams before exiting" do
      stream = double("stream")
      allow(stream).to receive(:flush)
      guard = described_class.new(register: register, exiter: exiter, streams: -> { [stream] })
      guard.install
      guard.status = 0

      run_hooks

      expect(stream).to have_received(:flush)
    end

    it "exits even when a stream is already closed" do
      stream = double("stream")
      allow(stream).to receive(:flush).and_raise(IOError)
      guard = described_class.new(register: register, exiter: exiter, streams: -> { [stream] })
      guard.install
      guard.status = 3

      run_hooks

      expect(exits).to eq([3])
    end
  end

  describe "#status=" do
    it "keeps the last status it was told" do
      guard.install
      guard.status = 1
      guard.status = 0

      run_hooks

      expect(exits).to eq([0])
    end
  end

  # Everything above injects its collaborators. This runs the real thing in a
  # child process: a real at_exit hook, a real exit! and a real flush, against a
  # competing hook of the kind a preloaded spec helper installs.
  describe "the defaults, in a real process" do
    def run_guarded(status:, competing_hook:)
      # The child gets this process's own load path, so under mutation testing it
      # loads the mutated copy rather than the pristine one.
      script = <<~RUBY
        $LOAD_PATH.replace(#{$LOAD_PATH.map(&:to_s).inspect})
        require "evilution"
        guard = Evilution::CLI::ExitGuard.new.install
        #{competing_hook}
        guard.status = #{status}
        exit guard.status
      RUBY
      output = IO.popen([RbConfig.ruby, "-e", script], err: %i[child out], &:read)
      [$CHILD_STATUS.exitstatus, output]
    end

    it "wins the exit status against a hook that exits non-zero" do
      status, = run_guarded(status: 0, competing_hook: "at_exit { exit 2 }")

      expect(status).to eq(0)
    end

    it "reports a failing status of its own" do
      status, = run_guarded(status: 1, competing_hook: "")

      expect(status).to eq(1)
    end

    def run_dying(error:, competing_hook: "", before_death: "")
      script = <<~RUBY
        $LOAD_PATH.replace(#{$LOAD_PATH.map(&:to_s).inspect})
        require "evilution"
        Evilution::CLI::ExitGuard.new.install
        #{competing_hook}
        mutation = Object.new
        def mutation.to_s = "constant_namespace_strip: lib/example.rb:202"
        Evilution::Isolation::InProcess.watch(mutation)
        #{before_death}
        raise #{error}
      RUBY
      output = IO.popen([RbConfig.ruby, "-e", script], err: %i[child out], &:read)
      [$CHILD_STATUS, output]
    end

    describe "when the process dies in the middle of a mutation under in-process isolation" do
      it "ends with the status of a tool error and says which mutation it was" do
        status, output = run_dying(error: 'Exception, "escaped everything"')

        expect(status.exitstatus).to eq(2)
        expect(output).to include(
          "[evilution] the run died while testing a mutation under in-process isolation: " \
          "constant_namespace_strip: lib/example.rb:202 (Exception: escaped everything)."
        )
      end

      it "keeps that status against a hook that exits with its own" do
        status, = run_dying(error: 'Exception, "escaped everything"', competing_hook: "at_exit { exit 7 }")

        expect(status.exitstatus).to eq(2)
      end

      it "lets the hooks installed after it run" do
        _status, output = run_dying(error: 'Exception, "escaped everything"', competing_hook: "at_exit { puts 'coverage report' }")

        expect(output).to include("coverage report")
      end

      # On such a death nothing puts `$stdout` and `$stderr` back: they are
      # still the null streams of a mutation under test. What the run printed
      # before went to the process's own, and standard output buffers when it
      # is a pipe.
      it "does not lose what the run printed before the mutation silenced it" do
        silenced = 'print "progress so far"; $stdout = $stderr = Evilution::Isolation::InProcess.null_out'

        _status, output = run_dying(error: 'Exception, "escaped everything"', before_death: silenced)

        expect(output).to include("progress so far")
      end

      it "leaves an interrupted run the status Ruby gives it" do
        status, output = run_dying(error: "Interrupt")

        expect(status.termsig).to eq(Signal.list["INT"])
        expect(output).not_to include("[evilution] the run died")
      end
    end

    # exit! does not flush, so the competing hook's output has to be pushed out
    # by the guard before it goes.
    it "does not swallow output written by the hook that ran before it" do
      _status, output = run_guarded(status: 0, competing_hook: "at_exit { puts 'coverage report' }")

      expect(output).to include("coverage report")
    end
  end
end
