# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "securerandom"
require_relative "../runner"
require_relative "../mutation"
require_relative "../subject"

# Runs one guaranteed-unobservable synthetic mutation through the configured
# integration + isolation at session start. The synthetic spec never references
# the synthetic class, so mutating the class cannot change any test outcome — a
# healthy pipeline must score the mutation :survived. Any other status means the
# mutation infrastructure is misreporting, so the run aborts before producing
# numbers that would all be unreliable. Mirrors the configured --isolation so
# isolation-specific defects are caught too.
class Evilution::Runner::Canary
  class Failed < Evilution::Error; end

  def initialize(config:, isolator:, integration_class:, hooks: nil)
    @config = config
    @isolator = isolator
    @integration_class = integration_class
    @hooks = hooks
  end

  def call
    dir = Dir.mktmpdir("evilution-canary")
    class_path = write_target_class(dir)
    spec_path = write_spec(dir)

    result = @isolator.call(
      mutation: build_mutation(class_path),
      test_command: ->(mutation) { build_integration(spec_path).call(mutation) },
      timeout: @config.timeout
    )
    raise Failed, failure_message(result.status) unless result.status == :survived

    nil
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  private

  # pid + random hex keeps the synthetic class/spec names unique across
  # concurrent sessions and across repeated re-eval into the same VM.
  def suffix
    @suffix ||= "#{Process.pid}_#{SecureRandom.hex(4)}"
  end

  def class_name
    @class_name ||= "EvilutionCanary_#{suffix}"
  end

  def original_source
    <<~RUBY
      class #{class_name}
        private

        def __evilution_canary_probe
          :original
        end
      end
    RUBY
  end

  def mutated_source
    original_source.sub(":original", "nil")
  end

  def write_target_class(dir)
    path = File.join(dir, "#{class_name.downcase}.rb")
    File.write(path, original_source)
    path
  end

  def write_spec(dir)
    path = File.join(dir, spec_filename)
    File.write(path, spec_source)
    path
  end

  # minitest and test-unit both live under a `_test.rb` file; rspec uses
  # `_spec.rb`. Picking the wrong shape makes the integration load nothing (or
  # raise), so the synthetic mutation scores :error and aborts the run.
  def spec_filename
    test_framework? ? "canary_#{suffix}_test.rb" : "canary_#{suffix}_spec.rb"
  end

  def test_framework?
    %i[minitest test_unit].include?(@config.integration)
  end

  def spec_source
    case @config.integration
    when :minitest then minitest_spec_source
    when :test_unit then test_unit_spec_source
    else rspec_spec_source
    end
  end

  def rspec_spec_source
    <<~RUBY
      RSpec.describe("evilution proof-of-life canary") do
        it "pipeline is alive" do
          expect(true).to be(true)
        end
      end
    RUBY
  end

  def minitest_spec_source
    <<~RUBY
      class EvilutionCanaryTest_#{suffix} < Minitest::Test
        def test_pipeline_is_alive
          assert true
        end
      end
    RUBY
  end

  def test_unit_spec_source
    <<~RUBY
      class EvilutionCanaryTest_#{suffix} < Test::Unit::TestCase
        def test_pipeline_is_alive
          assert(true)
        end
      end
    RUBY
  end

  def build_mutation(class_path)
    Evilution::Mutation.new(
      subject: Evilution::Subject.new(
        name: "#{class_name}#__evilution_canary_probe",
        file_path: class_path, line_number: 1, source: original_source, node: nil
      ),
      operator_name: :canary_probe,
      sources: Evilution::Mutation::Sources.new(original: original_source, mutated: mutated_source),
      location: Evilution::Mutation::Location.new(file_path: class_path, line: 5, column: 4)
    )
  end

  def build_integration(spec_path)
    @integration_class.new(test_files: [spec_path], hooks: @hooks)
  end

  def failure_message(status)
    "evilution proof-of-life canary failed: a guaranteed-unobservable synthetic " \
      "mutation was scored #{status.inspect} instead of :survived. The mutation " \
      "pipeline is misreporting — every score this run would produce is unreliable. " \
      "Likely causes: Rails/Zeitwerk autoloading breaking child eval; an env-specific " \
      "RSpec config (e.g. fail_if_no_examples); a classify_status fallback defect; or " \
      "an isolation-mode defect. Re-run with --no-canary to bypass this check."
  end
end
