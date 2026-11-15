# frozen_string_literal: true

require "json"

# Shared readers for the comparison scripts: a run's JSON report keyed by
# mutant identity, and the harness's stats file written next to it.
module SpikeResults
  STATUSES = %w[killed survived timed_out errors neutral equivalent unresolved unparseable uncovered].freeze

  module_function

  # { [file, line, operator, diff] => entry with "status" added }
  def rows(path)
    report = JSON.parse(File.read(path))
    STATUSES.flat_map do |status|
      (report[status] || []).map { |r| [key(r), r.merge("status" => status)] }
    end.to_h
  end

  def key(entry)
    [entry["file"], entry["line"], entry["operator"], entry["diff"]]
  end

  def stats_path(path)
    path.sub(/\.json\z/, ".stats.json")
  end

  def stats(path)
    JSON.parse(File.read(stats_path(path)))
  end

  def sum(rows, keys, field)
    keys.sum { |k| rows[k] ? rows[k][field].to_f : 0 }
  end

  def combined?(entry)
    entry["test_command"].to_s.start_with?("combined")
  end

  def ran?(entry)
    entry["duration"].to_f.positive?
  end
end
