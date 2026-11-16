# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs evilution for real over files whose class body goes on after a line a
# mutant can turn into freezing the class or module itself:
#
# - bag.rb builds its empty instance, `EMPTY = Bag.new([].freeze).freeze`, in a
#   class nothing else refers to;
# - crate_ext.rb reopens a class crate.rb defines, `LABEL = Crate.name.freeze`;
# - greeting.rb declares a module Person, in person.rb, includes.
#
# The mutant that drops the call in between (`EMPTY = Bag.freeze`) makes the
# rest of the body raise FrozenError. The original loads in any process that
# mutant has not touched, so the mutant broke the load and is detected. Under
# in_process the class stays frozen for the mutants of the file after it,
# which then cannot be judged; whatever is judged must agree with fork.
RSpec.describe "A mutant that freezes its own class while the file loads", :aggregate_failures do
  project = File.expand_path("../../support/fixtures/frozen_class_load_failure_project", __dir__)
  root = File.expand_path("../../..", __dir__)

  targets = {
    "lib/bag.rb" => { spec: "spec/bag_spec.rb", freezing: "EMPTY = Bag.freeze" },
    "lib/crate_ext.rb" => { spec: "spec/crate_ext_spec.rb", freezing: "LABEL = Crate.freeze" },
    "lib/greeting.rb" => { spec: "spec/greeting_spec.rb", freezing: "LABEL = Greeting.freeze" }
  }

  run_evilution = lambda do |target, isolation|
    Dir.mktmpdir("frozen_class_load_failure") do |dir|
      FileUtils.cp_r(File.join(project, "."), dir)
      # The fixture's specs are kept under another name so this suite does not
      # load them as its own.
      Dir.glob(File.join(dir, "spec/*.rb.fixture")).each { |path| FileUtils.mv(path, path.delete_suffix(".fixture")) }
      env = { "BUNDLE_GEMFILE" => ENV.fetch("BUNDLE_GEMFILE", File.join(root, "Gemfile")) }
      command = [RbConfig.ruby, "-rbundler/setup", "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run",
                 target, "--spec", targets.fetch(target).fetch(:spec), "--preload", "spec/spec_helper.rb",
                 "--isolation", isolation, "--format", "json"]
      out, err, status = Open3.capture3(env, *command, chdir: dir)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      report = JSON.parse(out)
      raise "evilution failed (#{status.exitstatus}): #{report["error"]}" if report.key?("error")

      report
    end
  end

  categories = %w[killed survived errors timed_out neutral equivalent unresolved unparseable uncovered]

  # Each mutant's category, keyed by what tells the mutants of one file apart.
  verdicts = lambda do |report|
    categories.each_with_object({}) do |category, found|
      report.fetch(category, []).each do |entry|
        found[entry.values_at("operator", "line", "diff")] = category
      end
    end
  end

  # One run per file and isolation, shared by the examples: each is a whole
  # evilution run in a process of its own, so they run side by side.
  before(:context) do
    runs = targets.keys.product(%w[fork in_process]).map do |target, isolation|
      Thread.new { [[target, isolation], run_evilution.call(target, isolation)] }
    end
    @reports = runs.to_h(&:value)
  end

  targets.each do |target, details|
    context "when mutating #{target}" do
      %w[fork in_process].each do |isolation|
        it "counts the freezing mutant as killed under #{isolation}, saying what the load raised" do
          report = @reports.fetch([target, isolation])
          freezing = report.fetch("killed").find { |entry| entry.fetch("diff").end_with?("+   #{details.fetch(:freezing)}") }

          expect(freezing).to include("error_class" => "FrozenError")
          expect(freezing.fetch("error_message")).to start_with("load failed: FrozenError: can't modify frozen ")
        end
      end

      it "reports no errors under fork" do
        report = @reports.fetch([target, "fork"])

        expect(report.dig("summary", "errors")).to eq(0)
        expect(report.fetch("errors", [])).to eq([])
      end

      # The class stays frozen in the in_process run, so the mutants after the
      # freezing one may be errors there; none may be killed or survive where
      # fork judged otherwise.
      it "judges every mutant under in_process as under fork, unless it reports an error" do
        fork = verdicts.call(@reports.fetch([target, "fork"]))
        in_process = verdicts.call(@reports.fetch([target, "in_process"]))
        disagreements = in_process.reject { |key, category| category == "errors" || category == fork[key] }

        expect(in_process.keys).to match_array(fork.keys)
        expect(disagreements).to eq({})
      end
    end
  end

  %w[fork in_process].each do |isolation|
    it "names the class the mutant froze under #{isolation}" do
      killed = @reports.fetch(["lib/bag.rb", isolation]).fetch("killed")
      freezing = killed.find { |entry| entry.fetch("diff").end_with?("+   EMPTY = Bag.freeze") }

      # Ruby versions word the frozen receiver differently.
      expect(freezing.fetch("error_message")).to match(/\Aload failed: FrozenError: can't modify frozen ([Cc]lass|#<Class:Bag>): Bag\z/)
    end
  end
end
