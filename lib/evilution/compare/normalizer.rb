# frozen_string_literal: true

require_relative "../compare"
require_relative "record"
require_relative "fingerprint"

class Evilution::Compare::Normalizer
  EVILUTION_BUCKETS = %w[killed survived timed_out errors neutral equivalent unresolved unparseable].freeze
  EVILUTION_STATUS_MAP = {
    "killed" => :killed,
    "survived" => :survived,
    "timeout" => :timeout,
    "error" => :error,
    "neutral" => :neutral,
    "equivalent" => :equivalent,
    "unresolved" => :unresolved,
    "unparseable" => :unparseable
  }.freeze

  def from_evilution(json)
    records = []
    EVILUTION_BUCKETS.each do |bucket|
      Array(json[bucket]).each do |entry|
        records << build_evilution_record(entry, index: records.size)
      end
    end
    records
  end

  def from_mutant(json)
    records = []
    Array(json["subject_results"]).each do |subject|
      source_path = subject["source_path"] or
        raise Evilution::Compare::InvalidInput.new("missing 'source_path' on subject", index: records.size)
      Array(subject["coverage_results"]).each do |cov|
        records << build_mutant_record(cov, source_path: source_path, index: records.size)
      end
    end
    records
  end

  private

  def build_evilution_record(entry, index:)
    file_path = entry["file"] or raise Evilution::Compare::InvalidInput.new("missing 'file' in record", index: index)
    line = entry["line"] or raise Evilution::Compare::InvalidInput.new("missing 'line' in record", index: index)
    diff = entry["diff"].to_s
    status = EVILUTION_STATUS_MAP[entry["status"]] ||
             raise(Evilution::Compare::InvalidInput.new("unknown status #{entry["status"].inspect}", index: index))
    body = Evilution::Compare::Fingerprint.extract_from_evilution_diff(diff)
    Evilution::Compare::Record.new(
      source: :evilution,
      file_path: file_path,
      line: line,
      status: status,
      fingerprint: Evilution::Compare::Fingerprint.compute(file_path: file_path, line: line, body: body),
      operator: entry["operator"],
      diff_body: diff,
      raw: entry
    )
  end

  def build_mutant_record(cov, source_path:, index:)
    mr = cov["mutation_result"] or raise Evilution::Compare::InvalidInput.new("missing mutation_result", index: index)
    cr = cov["criteria_result"] or raise Evilution::Compare::InvalidInput.new("missing criteria_result", index: index)
    ident = mr["mutation_identification"].to_s
    line = parse_mutant_line(ident, index)
    diff = mr["mutation_diff"].to_s
    status = derive_mutant_status(mr, cr, index)
    body = Evilution::Compare::Fingerprint.extract_from_mutant_diff(diff)
    Evilution::Compare::Record.new(
      source: :mutant,
      file_path: source_path,
      line: line,
      status: status,
      fingerprint: Evilution::Compare::Fingerprint.compute(file_path: source_path, line: line, body: body),
      operator: nil,
      diff_body: diff,
      raw: { "mutation_result" => mr, "criteria_result" => cr, "source_path" => source_path }
    )
  end

  # mutant_identification format: <type>:<subject>:<path>:<line>:<sha1[0..4]>.
  # Line is always the second-to-last colon-separated field. Works with paths
  # containing colons (e.g. Windows drive letters) because we index from the
  # right, but a malformed path-less identification will raise InvalidInput.
  def parse_mutant_line(ident, index)
    parts = ident.split(":")
    raise Evilution::Compare::InvalidInput.new("cannot parse line from #{ident.inspect}", index: index) if parts.length < 5

    Integer(parts[-2])
  rescue ArgumentError
    raise Evilution::Compare::InvalidInput.new("non-integer line in #{ident.inspect}", index: index)
  end

  # rubocop:disable Metrics/PerceivedComplexity
  def derive_mutant_status(mr, cr, index)
    type = mr["mutation_type"]
    return :neutral if %w[neutral noop].include?(type)
    return :timeout if cr["timeout"]
    return :error   if cr["process_abort"]
    return :killed  if cr["test_result"]
    return :survived if type == "evil" && !cr["process_abort"] && !cr["timeout"] && !cr["test_result"]

    raise Evilution::Compare::InvalidInput.new("unknown mutant result shape: type=#{type.inspect} cr=#{cr.inspect}", index: index)
  end
  # rubocop:enable Metrics/PerceivedComplexity
end
