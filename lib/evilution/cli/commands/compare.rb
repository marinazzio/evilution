# frozen_string_literal: true

require "json"
require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../../compare"
require_relative "../../compare/detector"
require_relative "../../compare/normalizer"

class Evilution::CLI::Commands::Compare < Evilution::CLI::Command
  ROLES = %i[against current].freeze

  private

  def perform
    paths = resolve_paths
    raise Evilution::ConfigError, "two file paths required for compare" unless paths.length == 2

    payload = ROLES.zip(paths).to_h { |role, path| [role, load_and_normalize(path)] }
    @stdout.puts JSON.generate(payload)
    0
  end

  # Flags bind to roles (--against -> slot 0, --current -> slot 1);
  # positional @files fill whatever role the flags didn't claim, in order.
  def resolve_paths
    positional = @files.dup
    against = @options[:against] || positional.shift
    current = @options[:current] || positional.shift
    [against, current].compact
  end

  def load_and_normalize(path)
    raise Evilution::Error, "file not found: #{path}" unless File.exist?(path)

    json = JSON.parse(File.read(path))
    tool = Evilution::Compare::Detector.call(json)
    records = normalize(json, tool)
    { path: path, tool: tool.to_s, records: records.map { |r| record_to_hash(r) } }
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

  # Data#to_h keeps symbol values for :source and :status, which
  # JSON.generate would reject. Stringify them for machine-friendly output.
  def record_to_hash(record)
    h = record.to_h
    h[:source] = h[:source].to_s
    h[:status] = h[:status].to_s
    h
  end
end

Evilution::CLI::Dispatcher.register(:compare, Evilution::CLI::Commands::Compare)
