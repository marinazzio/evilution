# frozen_string_literal: true

require_relative "../result"

class Evilution::Result::Summary
  attr_reader :results, :duration, :skipped

  def initialize(results:, duration: 0.0, truncated: false, skipped: 0)
    @results = results
    @duration = duration
    @truncated = truncated
    @skipped = skipped
    freeze
  end

  def truncated?
    @truncated
  end

  def total
    results.length
  end

  def killed
    results.count(&:killed?)
  end

  def survived
    results.count(&:survived?)
  end

  def timed_out
    results.count(&:timeout?)
  end

  def errors
    results.count(&:error?)
  end

  def neutral
    results.count(&:neutral?)
  end

  def equivalent
    results.count(&:equivalent?)
  end

  def score
    denominator = total - errors - neutral - equivalent
    return 0.0 if denominator.zero?

    killed.to_f / denominator
  end

  def success?(min_score: 1.0)
    score >= min_score
  end

  def survived_results
    results.select(&:survived?)
  end

  def killed_results
    results.select(&:killed?)
  end

  def neutral_results
    results.select(&:neutral?)
  end

  def equivalent_results
    results.select(&:equivalent?)
  end

  def killtime
    results.sum(0.0, &:duration)
  end

  def efficiency
    return 0.0 if duration.zero?

    killtime / duration
  end

  def mutations_per_second
    return 0.0 if duration.zero?

    total.to_f / duration
  end

  def peak_memory_mb
    max_rss = nil
    results.each do |result|
      kb = result.child_rss_kb
      next unless kb

      max_rss = kb if max_rss.nil? || kb > max_rss
    end

    max_rss && (max_rss / 1024.0)
  end
end
