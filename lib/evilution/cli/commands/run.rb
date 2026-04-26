# frozen_string_literal: true

require "json"
require_relative "../commands"
require_relative "../command"
require_relative "../result"
require_relative "../dispatcher"
require_relative "../../config"
require_relative "../../runner"
require_relative "../../hooks"
require_relative "../../hooks/registry"
require_relative "../../hooks/loader"
require_relative "../../feedback/messages"

class Evilution::CLI::Commands::Run < Evilution::CLI::Command
  def call
    file_options = Evilution::Config.file_options
    config = nil
    raise Evilution::ConfigError, @stdin_error if @stdin_error

    config = Evilution::Config.new(**@options, target_files: @files, line_ranges: @line_ranges)
    hooks = build_hooks(config)
    runner = Evilution::Runner.new(config: config, hooks: hooks)
    summary = runner.call
    exit_code = summary.success?(min_score: config.min_score) ? 0 : 1
    Evilution::CLI::Result.new(exit_code: exit_code)
  rescue Evilution::Error => e
    handle_error(e, config, file_options)
  end

  private

  def handle_error(error, config, file_options)
    if json_format?(config, file_options)
      @stdout.puts(JSON.generate(error_payload(error)))
      Evilution::CLI::Result.new(exit_code: 2, error: error, error_rendered: true)
    else
      @stderr.puts(Evilution::Feedback::Messages.cli_footer) unless quiet?(config, file_options)
      Evilution::CLI::Result.new(exit_code: 2, error: error)
    end
  end

  def quiet?(config, file_options)
    return config.quiet unless config.nil?
    return true if @options[:quiet]

    file_options && file_options[:quiet]
  end

  def build_hooks(config)
    return nil if config.hooks.empty?

    registry = Evilution::Hooks::Registry.new
    Evilution::Hooks::Loader.call(registry, config.hooks)
    registry
  end

  def json_format?(config, file_options)
    return config.json? if config

    fmt = @options[:format] || (file_options && file_options[:format])
    fmt && fmt.to_sym == :json
  end

  def error_payload(error)
    type = case error
           when Evilution::ConfigError then "config_error"
           when Evilution::ParseError  then "parse_error"
           else "runtime_error"
           end
    payload = { type: type, message: error.message }
    payload[:file] = error.file if error.respond_to?(:file) && error.file
    { error: payload }
  end
end

Evilution::CLI::Dispatcher.register(:run, Evilution::CLI::Commands::Run)
