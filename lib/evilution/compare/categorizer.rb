# frozen_string_literal: true

require_relative "../compare"
require_relative "record"

module Evilution::Compare::Categorizer
  ALIVE = %i[survived].freeze
  DEAD  = %i[killed timeout error].freeze
  # neutral, equivalent, unresolved, unparseable are non-actionable signals
  # — excluded from alive/dead buckets, counted in summary.

  module_function

  # @param against [Array<Record>] prior run (baseline)
  # @param current [Array<Record>] current run
  # @return [Hash] see module docs for bucket structure
  def call(against, current)
    # Duplicate fingerprints within one side should not happen (Normalizer
    # invariant). If they do, last write wins — we do not dedupe proactively.
    against_by_fp = index_by_fingerprint(against)
    current_by_fp = index_by_fingerprint(current)

    buckets = {
      alive_only_against: [],
      alive_only_current: [],
      shared_alive: [],
      shared_dead: [],
      excluded_against: 0,
      excluded_current: 0
    }

    (against_by_fp.keys | current_by_fp.keys).each do |fp|
      classify(against_by_fp[fp], current_by_fp[fp], buckets)
    end

    sort_buckets!(buckets)
    buckets
  end

  # Dispatches one fingerprint pair into buckets.
  # Either record may be nil (fingerprint present on only one side).
  def classify(against_record, current_record, buckets)
    count_excluded(against_record, current_record, buckets)
    a_kind = kind_of(against_record)
    c_kind = kind_of(current_record)

    if a_kind == :alive && c_kind == :alive
      buckets[:shared_alive] << { against: against_record, current: current_record }
    elsif a_kind == :dead && c_kind == :dead
      buckets[:shared_dead] << { against: against_record, current: current_record }
    else
      bucket_single_sided(against_record, current_record, a_kind, c_kind, buckets)
    end
    # A dead-only fingerprint (dead on one side, absent on the other) is
    # intentionally not bucketed and not counted as excluded.
  end

  def count_excluded(against_record, current_record, buckets)
    buckets[:excluded_against] += 1 if against_record && kind_of(against_record) == :excluded
    buckets[:excluded_current] += 1 if current_record && kind_of(current_record) == :excluded
  end

  def bucket_single_sided(against_record, current_record, a_kind, c_kind, buckets)
    # peer_status is the peer record's status symbol, or nil if peer absent.
    # When the peer is excluded, its status symbol (e.g. :neutral) flows through.
    a_peer = current_record && current_record.status
    c_peer = against_record && against_record.status
    buckets[:alive_only_against] << { record: against_record, peer_status: a_peer } if a_kind == :alive
    buckets[:alive_only_current] << { record: current_record, peer_status: c_peer } if c_kind == :alive
  end

  # Returns :alive, :dead, :excluded, or nil (for nil records).
  def kind_of(record)
    return nil if record.nil?
    return :alive if ALIVE.include?(record.status)
    return :dead  if DEAD.include?(record.status)

    :excluded
  end

  def sort_buckets!(buckets)
    buckets[:alive_only_against].sort_by! { |e| sort_key(e[:record]) }
    buckets[:alive_only_current].sort_by! { |e| sort_key(e[:record]) }
    buckets[:shared_alive].sort_by!       { |e| sort_key(e[:against]) }
    buckets[:shared_dead].sort_by!        { |e| sort_key(e[:against]) }
  end

  def sort_key(record)
    [record.file_path, record.line, record.fingerprint]
  end

  def index_by_fingerprint(records)
    records.to_h { |r| [r.fingerprint, r] }
  end
end
