# frozen_string_literal: true

require_relative "../runner"

# Explains why the proof-of-life canary failed, from the result its synthetic
# mutation came back with. Kept apart from Canary, which only runs the probe:
# the wording changes for different reasons than the mechanics do.
class Evilution::Runner::CanaryFailureMessage
  # Raised by RubyGems when it cannot load a gem at a version that satisfies
  # every requirement already in play.
  GEM_ACTIVATION_ERRORS = %w[
    Gem::ConflictError Gem::LoadError Gem::MissingSpecError Gem::MissingSpecVersionError
  ].freeze

  def initialize(result)
    @result = result
  end

  # When the child reported an error, that error IS the diagnosis -- naming it
  # beats guessing. The speculative list stays only for the cases that carry no
  # error at all (:killed, :timeout), where guesses are the only help there is.
  # Diagnosing GH #1581 meant rebuilding this canary by hand to read the field
  # this message used to drop, and none of the four guesses was the cause.
  # EV-65nf / GH #1586.
  def to_s
    return gem_activation_message(@result) if gem_activation_failure?(@result)

    "#{failure_preamble(@result.status)} #{diagnosis(@result)} " \
      "Re-run with --no-canary to bypass this check."
  end

  private

  # The usual cause is evilution running outside `bundle exec`: RubyGems then
  # activates the newest installed copy of a shared dependency, which the test
  # framework may not accept. Every mutation would fail the same way, so
  # skipping the canary would not help.
  def gem_activation_message(result)
    "evilution proof-of-life canary failed: the test framework could not be loaded " \
      "because of a gem activation conflict. This is an environment problem, not a " \
      "mutation-pipeline defect, and every mutation would fail the same way. Run " \
      "evilution under `bundle exec` so the project's Gemfile.lock decides gem versions " \
      "(for the MCP server: command `bundle`, args [\"exec\", \"evilution\", \"mcp\"]). " \
      "The child reported: #{reported_error(result)}"
  end

  # The class may arrive in its own field or only as the message prefix,
  # depending on which path packed the error.
  def gem_activation_failure?(result)
    message = result.error_message.to_s

    GEM_ACTIVATION_ERRORS.any? do |klass|
      result.error_class == klass || message.start_with?("#{klass}:")
    end
  end

  def failure_preamble(status)
    "evilution proof-of-life canary failed: a guaranteed-unobservable synthetic " \
      "mutation was scored #{status.inspect} instead of :survived. The mutation " \
      "pipeline is misreporting — every score this run would produce is unreliable."
  end

  def diagnosis(result)
    reported = reported_error(result)
    return speculative_causes if reported.nil?

    "The child reported: #{reported}"
  end

  def reported_error(result)
    message = result.error_message
    return nil if message.nil? || message.empty?

    described = with_class_prefix(message, result.error_class)
    frame = first_frame(result)
    frame.nil? ? described : "#{described} (at #{frame})"
  end

  # MutationApplier already prefixes the class onto the message it packs
  # ("#{e.class}: #{e.message}"), while other paths pack the bare message and
  # leave the class in its own field. Prefixing unconditionally would print
  # "NameError: NameError: ..." for the former.
  def with_class_prefix(message, klass)
    return message if klass.nil? || klass.empty? || message.start_with?("#{klass}:")

    "#{klass}: #{message}"
  end

  def first_frame(result)
    backtrace = result.error_backtrace
    return nil if backtrace.nil? || backtrace.empty?

    backtrace.first
  end

  def speculative_causes
    "Likely causes: Rails/Zeitwerk autoloading breaking child eval; an env-specific " \
      "RSpec config (e.g. fail_if_no_examples); a classify_status fallback defect; or " \
      "an isolation-mode defect."
  end
end
