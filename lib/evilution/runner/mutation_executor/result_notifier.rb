# frozen_string_literal: true

require_relative "../../reporter/progress_bar"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass
class Evilution::Runner::MutationExecutor; end unless defined?(Evilution::Runner::MutationExecutor) # rubocop:disable Lint/EmptyClass

class Evilution::Runner::MutationExecutor::ResultNotifier
  def initialize(config, hooks:, diagnostics:, on_result:)
    @config = config
    @hooks = hooks
    @diagnostics = diagnostics
    @on_result = on_result
    @survived_count = 0
    @progress_bar = nil
  end

  attr_reader :survived_count

  def start(total)
    @survived_count = 0
    @progress_bar = build_progress_bar(total)
  end

  def notify(result, index)
    @on_result.call(result) if @on_result
    @progress_bar.tick(status: result.status) if @progress_bar
    @diagnostics.log_progress(index, result.status)
    @diagnostics.log_mutation_diagnostics(result)
    @survived_count += 1 if result.survived?
    truncate? ? :truncate : :continue
  end

  def finish
    @progress_bar.finish if @progress_bar
  end

  private

  def truncate?
    @config.fail_fast? && @survived_count >= @config.fail_fast
  end

  def build_progress_bar(total)
    return nil if !@config.progress? || @config.quiet || @config.verbose || !@config.text? || !$stderr.tty?

    Evilution::Reporter::ProgressBar.new(total: total, output: $stderr)
  end
end
