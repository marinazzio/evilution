# frozen_string_literal: true

require "set"
require_relative "../session"

class Evilution::Session::Diff
  Result = Struct.new(:summary, :fixed, :new_survivors, :persistent) do
    def to_h
      {
        "summary" => summary.to_h,
        "fixed" => fixed,
        "new_survivors" => new_survivors,
        "persistent" => persistent
      }
    end
  end

  SummaryDiff = Struct.new(
    :base_score, :head_score, :score_delta,
    :base_survived, :head_survived,
    :base_total, :head_total,
    :base_killed, :head_killed
  ) do
    def to_h
      {
        "base_score" => base_score,
        "head_score" => head_score,
        "score_delta" => score_delta,
        "base_survived" => base_survived,
        "head_survived" => head_survived,
        "base_total" => base_total,
        "head_total" => head_total,
        "base_killed" => base_killed,
        "head_killed" => head_killed
      }
    end
  end

  def call(base_data, head_data)
    base_survivors = base_data["survived"] || []
    head_survivors = head_data["survived"] || []

    base_keys = base_survivors.to_set { |m| mutation_key(m) }
    head_keys = head_survivors.to_set { |m| mutation_key(m) }

    Result.new(
      summary: build_summary_diff(base_data, head_data),
      fixed: base_survivors.reject { |m| head_keys.include?(mutation_key(m)) },
      new_survivors: head_survivors.reject { |m| base_keys.include?(mutation_key(m)) },
      persistent: head_survivors.select { |m| base_keys.include?(mutation_key(m)) }
    )
  end

  private

  def build_summary_diff(base_data, head_data)
    base = extract_summary_values(base_data)
    head = extract_summary_values(head_data)

    SummaryDiff.new(
      base_score: base[:score],
      head_score: head[:score],
      score_delta: (head[:score] - base[:score]).round(4),
      base_survived: base[:survived],
      head_survived: head[:survived],
      base_total: base[:total],
      head_total: head[:total],
      base_killed: base[:killed],
      head_killed: head[:killed]
    )
  end

  def extract_summary_values(data)
    summary = data["summary"] || {}
    {
      score: summary["score"] || 0.0,
      survived: summary["survived"] || 0,
      total: summary["total"] || 0,
      killed: summary["killed"] || 0
    }
  end

  def mutation_key(mutation)
    [mutation["operator"], mutation["file"], mutation["line"], mutation["subject"]]
  end
end
