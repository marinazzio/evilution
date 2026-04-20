# frozen_string_literal: true

require "json"
require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../printers/compare"
require_relative "../../compare"
require_relative "../../compare/categorizer"
require_relative "../../compare/detector"
require_relative "../../compare/normalizer"

class Evilution::CLI::Commands::Compare < Evilution::CLI::Command
  SUPPORTED_FORMATS = %i[json text].freeze

  private

  def perform
    paths = resolve_paths
    raise Evilution::ConfigError, "exactly two file paths required for compare" unless paths.length == 2

    fmt = @options[:format] || :json
    raise Evilution::ConfigError, "compare supports --format text or json, got #{fmt.inspect}" unless SUPPORTED_FORMATS.include?(fmt)

    against = load_and_normalize(paths[0])
    current = load_and_normalize(paths[1])
    buckets = Evilution::Compare::Categorizer.call(against, current)
    Evilution::CLI::Printers::Compare.new(buckets, format: fmt).render(@stdout)
    0
  end

  # Flags bind to roles (--against -> slot 0, --current -> slot 1);
  # positional @files fill whatever role the flags didn't claim, in order.
  # Extra positional args after both slots are filled are a user error.
  def resolve_paths
    positional = @files.dup
    against = @options[:against] || positional.shift
    current = @options[:current] || positional.shift

    raise Evilution::ConfigError, "exactly two file paths required for compare" unless positional.empty?

    [against, current].compact
  end

  def load_and_normalize(path)
    raise Evilution::Error, "file not found: #{path}" unless File.exist?(path)

    json = JSON.parse(File.read(path))
    tool = Evilution::Compare::Detector.call(json)
    normalize(json, tool)
  rescue ::JSON::ParserError => e
    raise Evilution::Error, "invalid JSON in #{path}: #{e.message}"
  rescue Evilution::Compare::InvalidInput => e
    raise Evilution::Error, "#{path}: #{e.message}"
  rescue SystemCallError => e
    raise Evilution::Error, e.message
  end

  def normalize(json, tool)
    normalizer = Evilution::Compare::Normalizer.new
    case tool
    when :mutant    then normalizer.from_mutant(json)
    when :evilution then normalizer.from_evilution(json)
    end
  end
end

Evilution::CLI::Dispatcher.register(:compare, Evilution::CLI::Commands::Compare)
