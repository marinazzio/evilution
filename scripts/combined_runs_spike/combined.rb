# frozen_string_literal: true

# Combined-runs spike harness, loaded with `RUBYOPT=-r<this file>`.
#
#   EV_COMBINED=1              run eligible mutants in combined groups (else: plan + stats only)
#   EV_COMBINED_CAP=<n>        max members per group (0 = no cap, the default)
#   EV_COMBINED_DISTINCT=1     members of a group must belong to different subjects
#   EV_COMBINED_OUT=<path>     write the plan, stats and per-group outcomes (JSON) from the parent
#
# Needs `--example-targeting coverage` (RSpec): the per-example coverage map
# says which examples execute each changed line.
#
# Eligible mutant: not runless (unparseable / uncovered / probe), its file is
# built in the map, the examples covering its reported line are known (so its
# single run is a coverage-targeted one), and every changed line that ran at
# all ran inside some example (a line that only ran while the file loaded --
# a constant, a class-body call, a `def` signature -- can reach any example).
# Its "affecting set" is the union of the examples covering its changed lines.
#
# Grouping: greedy first fit in the run's own order; a mutant joins the first
# group whose members' affecting sets are all disjoint from its own and, in the
# same file, whose changed byte ranges do not touch its own.
#
# Group run (one forked process per group, `--jobs` at a time): apply every
# member (members of one file merged into one source, evaluated once), run the
# union of the members' targeted examples once, killer-first ordered as a
# single run would be. A member whose example fails is killed, by that
# example; its remaining examples are skipped (per-member stop on kill); when
# every member is killed the run stops. A member with no failing example, or
# whose failure is an infrastructure crash, falls back to a normal single run
# (targeted + confirmation), as does every member of a group that failed to
# apply, crashed, or timed out (limit = sum of the members' limits).
require "bundler/setup"
require "json"
require "tmpdir"
require "stringio"
require "evilution"
require "evilution/runner/mutation_executor"
require "evilution/coverage/map_builder"

module CombinedSpike
  Member = Struct.new(:index, :mutation, :targets, :affecting, :eval_region, :src_region, :subject_key)

  class << self
    def enabled? = ENV["EV_COMBINED"] == "1"
    def cap = Integer(ENV.fetch("EV_COMBINED_CAP", "0"))
    def distinct? = ENV["EV_COMBINED_DISTINCT"] == "1"
    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def key(mutation)
      [mutation.file_path, mutation.line, mutation.operator_name, mutation.diff]
    end

    # [start, end, replacement] in bytes, a's range replaced to give b.
    def region(a, b)
      a = a.b
      b = b.b
      max = [a.bytesize, b.bytesize].min
      lo = 0
      hi = max
      while lo < hi
        mid = (lo + hi + 1) / 2
        a.byteslice(0, mid) == b.byteslice(0, mid) ? lo = mid : hi = mid - 1
      end
      prefix = lo
      lo = 0
      hi = max - prefix
      while lo < hi
        mid = (lo + hi + 1) / 2
        a.byteslice(a.bytesize - mid, mid) == b.byteslice(b.bytesize - mid, mid) ? lo = mid : hi = mid - 1
      end
      suffix = lo
      [prefix, a.bytesize - suffix, b.byteslice(prefix, b.bytesize - suffix - prefix)]
    end

    def splice(base, regions)
      out = base.b
      regions.sort_by { |r| -r[0] }.each { |s, e, rep| out = out.byteslice(0, s) + rep + out.byteslice(e, out.bytesize - e) }
      out.force_encoding(base.encoding)
    end

    def touch?(r1, r2) = r1[0] <= r2[1] && r2[0] <= r1[1]
  end

  # Decides eligibility and groups, in the parent.
  class Planner
    attr_reader :stats, :members, :reasons

    def initialize(integration:, runless:)
      @integration = integration
      @runless = runless
      @stats = Hash.new(0)
      @reasons = {}
    end

    def filter
      applier = @integration.instance_variable_get(:@example_filter_applier)
      inner = applier && applier.instance_variable_get(:@filter)
      inner.is_a?(Evilution::CoverageExampleFilter) ? inner : nil
    end

    def call(mutations, cap:, distinct:)
      cov = filter
      @members = []
      mutations.each_with_index do |m, i|
        reason, member = classify(m, i, cov)
        @reasons[i] = reason
        @stats["ineligible:#{reason}"] += 1 if reason
        @members << member if member
      end
      @stats["total"] = mutations.size
      @stats["eligible"] = @members.size
      group(@members, cap, distinct)
    end

    def group(members, cap, distinct)
      groups = []
      members.each do |m|
        g = groups.find { |grp| fits?(grp, m, cap, distinct) }
        g ? g[:members] << m : groups << { members: [m], examples: Set.new }
        (g || groups.last)[:examples].merge(m.affecting)
      end
      groups.map { |g| g[:members] }
    end

    private

    def fits?(grp, m, cap, distinct)
      return false if cap.positive? && grp[:members].size >= cap
      return false if grp[:examples].intersect?(m.affecting)

      grp[:members].none? do |o|
        (distinct && o.subject_key == m.subject_key) ||
          (o.mutation.file_path == m.mutation.file_path &&
            (CombinedSpike.touch?(o.eval_region, m.eval_region) || o.mutation.restore_source != m.mutation.restore_source))
      end
    end

    def classify(m, index, cov)
      return [:runless, nil] if @runless.call(m)
      return [:no_coverage_filter, nil] unless cov
      return [:no_restore_source, nil] if m.restore_source.nil?

      resolver = @integration.instance_variable_get(:@test_file_resolver)
      files = resolver.call(m, warn: false)
      return [:no_spec, nil] if files.nil?

      map = cov.instance_variable_get(:@map)
      file = File.expand_path(m.file_path, Evilution::PROJECT_ROOT)
      return [:file_not_built, nil] unless map.built?(file)

      targets = map.examples_for(file, m.line)
      return [:line_not_attributed, nil] if targets.empty? # single run is lexical

      affecting = Set.new(targets)
      m.changed_lines.each do |line|
        ex = map.examples_for(file, line)
        return [:load_only_line, nil] if ex.empty? && map.executed?(file, line)

        affecting.merge(ex)
      end
      subject = m.subject ? [m.file_path, m.subject.name] : [m.file_path, m.line]
      member = Member.new(index, m, targets, affecting,
                          CombinedSpike.region(m.restore_source, m.eval_source),
                          CombinedSpike.region(m.original_source, m.mutated_source), subject)
      [nil, member]
    end
  end

  # Runs groups in forked processes, `jobs` at a time, in the parent.
  class GroupRunner
    def initialize(integration:, jobs:, timeout_policy:, kill_history:)
      @integration = integration
      @jobs = jobs
      @timeout_policy = timeout_policy
      @kill_history = kill_history
    end

    def call(groups)
      queue = groups.each_with_index.to_a
      running = {}
      outcomes = {}
      until queue.empty? && running.empty?
        while running.size < @jobs && !queue.empty?
          grp, gi = queue.shift
          running[gi] = spawn(grp)
        end
        sleep 0.002
        running.each do |gi, r|
          if !r[:thread].alive?
            outcomes[gi] = finish(r, r[:thread].value)
            yield gi, outcomes[gi] if block_given?
          elsif CombinedSpike.now > r[:deadline]
            kill(r)
            outcomes[gi] = finish(r, { group_error: "timeout" })
          end
        end
        outcomes.each_key { |gi| running.delete(gi) }
      end
      outcomes
    end

    private

    def finish(r, payload)
      payload = { group_error: "no result (child died)" } if payload.nil?
      payload.merge(duration: CombinedSpike.now - r[:started], pid: r[:pid])
    end

    def kill(r)
      Process.kill("KILL", -r[:pid])
    rescue Errno::ESRCH
      nil
    ensure
      begin
        Process.wait(r[:pid])
      rescue Errno::ECHILD
        nil
      end
    end

    def spawn(grp)
      limit = grp.sum { |m| @timeout_policy.call(m.mutation) }
      killers = grp.flat_map { |m| @kill_history.killers_for(m.mutation) }.uniq
      @integration.prioritize(killers)
      read_io, write_io = IO.pipe
      read_io.binmode
      write_io.binmode
      started = CombinedSpike.now
      pid = fork do
        Process.setpgid(0, 0)
        read_io.close
        sandbox = Dir.mktmpdir("evilution-run")
        ENV["TMPDIR"] = sandbox
        Dir.chdir(sandbox)
        Evilution.in_isolated_worker!
        Evilution.single_mutation_process!
        $stdout.reopen(File::NULL, "w")
        $stderr.reopen(File::NULL, "w")
        result = begin
          ChildRun.new(@integration, grp).call
        rescue ScriptError, StandardError => e
          { group_error: "#{e.class}: #{e.message}", backtrace: Array(e.backtrace).first(5) }
        end
        write_io.write(Marshal.dump(result))
        write_io.close
        exit!(0)
      end
      write_io.close
      thread = Thread.new do
        data = read_io.read
        read_io.close
        begin
          Process.wait(pid)
        rescue Errno::ECHILD
          nil
        end
        data.empty? ? nil : Marshal.load(data) # rubocop:disable Security/MarshalLoad
      end
      { pid: pid, thread: thread, started: started, deadline: started + limit }
    end
  end

  # Inside the group's forked process.
  class ChildRun
    def initialize(integration, members)
      @integration = integration
      @members = members
    end

    def call
      @integration.send(:ensure_framework_loaded)
      applier = @integration.instance_variable_get(:@mutation_applier)
      t0 = CombinedSpike.now
      merged_mutations.each do |mm|
        err = applier.call(mm)
        return { group_error: "apply: #{err[:error]}", apply_error: true } if err
      end
      apply = CombinedSpike.now - t0
      run_examples.merge(apply: apply)
    end

    private

    def merged_mutations
      @members.group_by { |m| m.mutation.file_path }.map do |_file, ms|
        next ms.first.mutation if ms.size == 1

        first = ms.first.mutation
        eval_src = CombinedSpike.splice(first.restore_source, ms.map(&:eval_region))
        mutated = CombinedSpike.splice(first.original_source, ms.map(&:src_region))
        Evilution::Mutation.new(
          subject: first.subject, operator_name: "combined",
          sources: Evilution::Mutation::Sources.new(original: first.original_source, mutated: mutated),
          location: first.location, eval_source: eval_src, restore_source: first.restore_source
        )
      end
    end

    def run_examples
      owner = {}
      @members.each_with_index { |m, i| m.affecting.each { |loc| owner[loc] = i } }
      targets = @members.flat_map(&:targets).uniq
      root = Evilution::PROJECT_ROOT.to_s
      killed = {}
      infra = {}
      unattributed = []
      counts = Hash.new(0)
      known = @integration.instance_variable_get(:@known_failures)
      size = @members.size
      ::RSpec.configure do |config|
        config.around(:each) do |example|
          loc = Evilution::Coverage::MapBuilder.absolute_location(example.metadata[:location].to_s, root)
          i = owner[loc]
          skip("combined: member already killed") if i && killed.key?(i)
          example.run
          exc = example.exception
          if exc
            id = Evilution::Integration::RSpec::ExampleIds.of(example)
            if i.nil?
              unattributed << loc
            elsif Evilution::InfraCrash.class_name?(exc.class.name)
              infra[i] = id
            elsif !known.include?(id)
              killed[i] ||= id
              ::RSpec.world.wants_to_quit = true if killed.size == size
            end
          end
          counts[i] += 1
        end
      end
      kf = @integration.instance_variable_get(:@killer_first)
      ordered = kf.applies?
      order = ordered ? Evilution::Integration::RSpec::ExampleOrder::NAME.to_s : "defined"
      files = Evilution::Integration::RSpec::TargetResolver.new.call(targets)
      out = StringIO.new
      err = StringIO.new
      @integration.send(:reset_examples)
      @integration.send(:claim_rspec_streams, out, err)
      status = kf.during(ordered) do
        ::RSpec::Core::Runner.run(["--format", "progress", "--no-color", "--order", order, *files], err, out)
      end
      loaded = ::RSpec.world.example_count
      # An error outside every example (a spec file that fails to load, a
      # context hook) is nobody's kill: the whole group falls back.
      outside = ::RSpec.world.respond_to?(:non_example_failure) && ::RSpec.world.non_example_failure
      return { group_error: "failure outside examples", status: status, loaded: loaded } if outside

      {
        status: status, loaded: loaded, killed: killed, infra: infra, unattributed: unattributed,
        examples_run: Evilution::Integration::RSpec::ExampleIds.executed_count(::RSpec.world),
        per_member_examples: counts
      }
    end
  end

  module ExecutorPatch
    private

    def run_batch(notifier, pipeline, mutations, baseline_result, integration)
      planner = CombinedSpike::Planner.new(integration: integration, runless: @runless)
      groups = planner.call(mutations, cap: CombinedSpike.cap, distinct: CombinedSpike.distinct?)
      report = { "stats" => planner.stats, "groups" => groups.map(&:size).tally.sort.to_h,
                 "plan" => groups.map { |g| g.map { |m| CombinedSpike.key(m.mutation) } },
                 "ineligible" => planner.reasons.compact.map { |i, r| [CombinedSpike.key(mutations[i]), r] },
                 "caps" => caps_report(planner) }
      single = ->(muts) { super(notifier, pipeline, muts, baseline_result, integration) }
      return write_report(report) { single.call(mutations) } unless CombinedSpike.enabled?

      combined_batch(report, groups, mutations, integration, single)
    end

    def caps_report(planner)
      [2, 4, 8, 16, 0].to_h do |c|
        gs = planner.group(planner.members, c, CombinedSpike.distinct?)
        [c, { "groups" => gs.count { |g| g.size > 1 }, "grouped_members" => gs.select { |g| g.size > 1 }.sum(&:size),
              "plan" => gs.map { |g| g.map { |m| CombinedSpike.key(m.mutation) } } }]
      end
    end

    def write_report(report)
      result = yield
      File.write(ENV["EV_COMBINED_OUT"], JSON.generate(report)) if ENV["EV_COMBINED_OUT"]
      result
    end

    def combined_batch(report, groups, mutations, integration, single)
      multi = groups.select { |g| g.size > 1 }
      t0 = CombinedSpike.now
      runner = CombinedSpike::GroupRunner.new(integration: integration, jobs: @config.jobs,
                                              timeout_policy: @timeout_policy, kill_history: @kill_history)
      # Kills are recorded as each group finishes, so the groups that start
      # later run their members' known killers first, as single runs do.
      outcomes = runner.call(multi) do |gi, o|
        next if o[:group_error]

        o[:killed].each { |i, id| @kill_history.record(multi[gi][i].mutation, status: :killed, killing_test: id) }
      end
      group_phase = CombinedSpike.now - t0
      done = {}
      results = []
      outcome_log = []
      multi.each_with_index do |grp, gi|
        o = outcomes[gi]
        outcome_log << { "size" => grp.size, "duration" => o[:duration].round(4), "error" => o[:group_error],
                         "killed" => (o[:killed] || {}).size, "examples_run" => o[:examples_run],
                         "loaded" => o[:loaded], "unattributed" => o[:unattributed], "infra" => (o[:infra] || {}).size,
                         "members" => grp.map { |m| CombinedSpike.key(m.mutation) },
                         "killed_members" => (o[:killed] || {}).keys }
        next if o[:group_error] || o[:unattributed].to_a.any? || o[:loaded].to_i.zero?

        o[:killed].each do |i, id|
          m = grp[i]
          next if o[:infra].key?(i)

          done[m.index] = true
          m.mutation.strip_sources!
          results << Evilution::Result::MutationResult.new(
            mutation: m.mutation, status: :killed, duration: o[:duration] / grp.size,
            killing_test: id, test_command: "combined group #{gi}", examples_run: o[:per_member_examples][i]
          )
        end
      end
      rest = mutations.each_with_index.reject { |_m, i| done[i] }.map(&:first)
      if ENV.fetch("EV_COMBINED_DIRECT_CONFIRM", "1") == "1"
        multi.each_with_index do |grp, gi|
          o = outcomes[gi]
          next if o[:group_error] || o[:unattributed].to_a.any? || o[:loaded].to_i.zero?

          grp.each_with_index do |m, i|
            CombinedSpike::DIRECT[CombinedSpike.key(m.mutation)] = true unless o[:killed].key?(i) || o[:infra].key?(i)
          end
        end
      end
      t1 = CombinedSpike.now
      execution = single.call(rest)
      report.merge!("group_phase_seconds" => group_phase, "rest_phase_seconds" => CombinedSpike.now - t1,
                    "group_runs" => multi.size, "killed_in_groups" => results.size, "rest_mutations" => rest.size,
                    "outcomes" => outcome_log)
      File.write(ENV["EV_COMBINED_OUT"], JSON.generate(report)) if ENV["EV_COMBINED_OUT"]
      Evilution::Runner::MutationExecutor::ExecutionResult.new(
        results: results + execution.results, truncated: execution.truncated,
        infra_retried: execution.infra_retried, worker_stats: execution.worker_stats
      )
    end
  end

  # A member that passed its targeted examples in a group goes straight to the
  # confirming run over the whole resolved spec file (EV_COMBINED_DIRECT_CONFIRM,
  # on by default): its targeted run already passed once.
  DIRECT = {} # rubocop:disable Style/MutableConstant

  module DirectConfirm
    private

    def run_tests(mutation)
      return super unless DIRECT[CombinedSpike.key(mutation)]

      files = @test_file_resolver.call(mutation)
      return super if files.nil?

      confirm_run({}, files)
    end
  end
end

Evilution::Runner::MutationExecutor.prepend(CombinedSpike::ExecutorPatch)
Evilution::Integration::RSpec.prepend(CombinedSpike::DirectConfirm)
