# frozen_string_literal: true

require "json"
require_relative "../printers"

class Evilution::CLI::Printers::Compare
  SCHEMA = {
    "shared" => %w[file line operator fp],
    "alive_only" => %w[file line operator fp other_status]
  }.freeze

  FILE_LINE_WIDTH = 40
  OPERATOR_WIDTH  = 22
  FP_LENGTH       = 7
  MUTANT_OPERATOR = "(mutant)"
  ABSENT_STATUS   = "absent"

  def initialize(buckets, format: :json)
    @buckets = buckets
    @format  = format || :json
  end

  def render(io)
    case @format
    when :json then render_json(io)
    when :text then render_text(io)
    else raise Evilution::Error, "unknown compare format: #{@format.inspect}"
    end
  end

  private

  def render_json(io)
    payload = {
      "schema" => SCHEMA,
      "summary" => summary_hash,
      "alive_only_against" => @buckets[:alive_only_against].map { |e| alive_entry_array(e) },
      "alive_only_current" => @buckets[:alive_only_current].map { |e| alive_entry_array(e) },
      "shared_alive" => @buckets[:shared_alive].map { |e| shared_entry_array(e) },
      "shared_dead" => @buckets[:shared_dead].map { |e| shared_entry_array(e) }
    }
    io.puts(JSON.generate(payload))
  end

  def render_text(io)
    io.puts("Compare results")
    io.puts("-" * 15)
    io.puts(summary_line)

    if fully_empty?
      io.puts("No mutations to compare.")
      return
    end

    print_alive_block(io, :alive_only_against, "current")
    print_alive_block(io, :alive_only_current, "against")
    print_shared_block(io, :shared_alive)
    print_shared_block(io, :shared_dead)
  end

  def summary_hash
    against_count = @buckets[:alive_only_against].length
    current_count = @buckets[:alive_only_current].length
    {
      "alive_only_against" => against_count,
      "alive_only_current" => current_count,
      "shared_alive" => @buckets[:shared_alive].length,
      "shared_dead" => @buckets[:shared_dead].length,
      "excluded_against" => @buckets[:excluded_against],
      "excluded_current" => @buckets[:excluded_current],
      "delta" => current_count - against_count
    }
  end

  def summary_line
    s = summary_hash
    parts = [
      "summary:",
      "alive_only_against=#{s["alive_only_against"]}",
      "alive_only_current=#{s["alive_only_current"]}",
      "shared_alive=#{s["shared_alive"]}",
      "shared_dead=#{s["shared_dead"]}",
      "excluded=#{s["excluded_against"]}/#{s["excluded_current"]}",
      "delta=#{format_delta(s["delta"])}"
    ]
    parts.join(" ")
  end

  def format_delta(delta)
    return "\u00B10" if delta.zero?

    format("%+d", delta)
  end

  def fully_empty?
    @buckets[:alive_only_against].empty? &&
      @buckets[:alive_only_current].empty? &&
      @buckets[:shared_alive].empty? &&
      @buckets[:shared_dead].empty? &&
      @buckets[:excluded_against].zero? &&
      @buckets[:excluded_current].zero?
  end

  def alive_entry_array(entry)
    r = entry[:record]
    peer = entry[:peer_status]
    peer_str = peer.nil? ? ABSENT_STATUS : peer.to_s
    [r.file_path, r.line, r.operator, r.fingerprint, peer_str]
  end

  def shared_entry_array(entry)
    r = entry[:against]
    [r.file_path, r.line, r.operator, r.fingerprint]
  end

  def print_alive_block(io, bucket_key, peer_side_label)
    entries = @buckets[bucket_key]
    return if entries.empty?

    io.puts("")
    io.puts("#{bucket_key} (#{entries.length}):")
    entries.each { |entry| io.puts(format_alive_row(entry, peer_side_label)) }
  end

  def print_shared_block(io, bucket_key)
    entries = @buckets[bucket_key]
    return if entries.empty?

    io.puts("")
    io.puts("#{bucket_key} (#{entries.length}):")
    entries.each { |entry| io.puts(format_shared_row(entry)) }
  end

  def format_alive_row(entry, peer_side_label)
    r = entry[:record]
    peer = entry[:peer_status]
    peer_str = peer.nil? ? ABSENT_STATUS : peer.to_s
    "  #{row_prefix(r)}  (#{peer_side_label}: #{peer_str})"
  end

  def format_shared_row(entry)
    r = entry[:against]
    "  #{row_prefix(r)}"
  end

  def row_prefix(record)
    file_line = "#{record.file_path}:#{record.line}"
    operator  = record.operator || MUTANT_OPERATOR
    fp        = record.fingerprint.to_s[0, FP_LENGTH]
    "#{file_line.ljust(FILE_LINE_WIDTH)}#{operator.ljust(OPERATOR_WIDTH)}#{fp}"
  end
end
