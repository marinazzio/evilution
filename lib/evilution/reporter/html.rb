# frozen_string_literal: true

require "cgi"
require_relative "suggestion"

require_relative "../reporter"
require_relative "../result/coverage_gap_grouper"

class Evilution::Reporter::HTML
  def initialize(baseline: nil, integration: :rspec)
    @suggestion = Evilution::Reporter::Suggestion.new(integration: integration)
    @baseline = baseline
    @baseline_keys = build_baseline_keys(baseline)
  end

  def call(summary)
    files = group_by_file(summary.results)
    build_html(summary, files)
  end

  private

  def group_by_file(results)
    grouped = {}
    results.each do |result|
      path = result.mutation.file_path
      grouped[path] ||= []
      grouped[path] << result
    end
    grouped.sort_by { |path, _| path }.to_h
  end

  def build_html(summary, files)
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Evilution Mutation Report</title>
        #{stylesheet}
      </head>
      <body>
        #{build_header(summary)}
        #{build_summary_cards(summary)}
        #{build_baseline_comparison(summary)}
        #{build_truncation_notice(summary)}
        #{build_file_sections(files)}
        #{build_footer}
      </body>
      </html>
    HTML
  end

  def build_header(summary)
    score_pct = format("%.2f%%", summary.score * 100)
    score_class = score_css_class(summary.score)
    <<~HTML
      <header>
        <h1>Evilution <span class="version">v#{h(Evilution::VERSION)}</span></h1>
        <div class="score-badge #{score_class}">#{score_pct}</div>
      </header>
    HTML
  end

  def build_summary_cards(summary)
    peak = summary.peak_memory_mb
    peak_html = if peak
                  peak_val = format("%.1f", peak)
                  "<div class=\"card\"><span class=\"card-value\">#{peak_val} MB</span>" \
                    "<span class=\"card-label\">Peak Memory</span></div>"
                else
                  ""
                end
    <<~HTML
      <section class="summary-cards">
        <div class="card"><span class="card-value">#{summary.total}</span><span class="card-label">Total</span></div>
        <div class="card card-killed"><span class="card-value">#{summary.killed}</span><span class="card-label">Killed</span></div>
        <div class="card card-survived"><span class="card-value">#{summary.survived}</span><span class="card-label">Survived</span></div>
        <div class="card"><span class="card-value">#{summary.timed_out}</span><span class="card-label">Timed Out</span></div>
        <div class="card"><span class="card-value">#{summary.errors}</span><span class="card-label">Errors</span></div>
        <div class="card"><span class="card-value">#{summary.neutral}</span><span class="card-label">Neutral</span></div>
        <div class="card"><span class="card-value">#{summary.equivalent}</span><span class="card-label">Equivalent</span></div>
        #{build_skipped_card(summary)}
        <div class="card"><span class="card-value">#{format("%.2f", summary.duration)}s</span><span class="card-label">Duration</span></div>
        #{build_efficiency_cards(summary)}
        #{peak_html}
      </section>
    HTML
  end

  def build_efficiency_cards(summary)
    return "" unless summary.duration.positive?

    pct = format("%.1f%%", summary.efficiency * 100)
    rate = format("%.2f", summary.mutations_per_second)
    %(<div class="card"><span class="card-value">#{pct}</span><span class="card-label">Efficiency</span></div>) +
      %(<div class="card"><span class="card-value">#{rate}/s</span><span class="card-label">Rate</span></div>)
  end

  def build_skipped_card(summary)
    return "" unless summary.skipped.positive?

    %(<div class="card"><span class="card-value">#{summary.skipped}</span><span class="card-label">Skipped</span></div>)
  end

  def build_truncation_notice(summary)
    return "" unless summary.truncated?

    '<div class="truncation-notice">Truncated: Stopped early due to --fail-fast</div>'
  end

  def build_file_sections(files)
    return '<p class="empty">No mutations generated.</p>' if files.empty?

    files.map { |path, results| build_file_section(path, results) }.join("\n")
  end

  def build_file_section(path, results)
    killed_count = results.count(&:killed?)
    survived_count = results.count(&:survived?)
    total = results.length
    survived = results.select(&:survived?)
    map_html = build_mutation_map(results)

    <<~HTML
      <section class="file-section">
        <h2 class="file-header">
          <span class="file-path">#{h(path)}</span>
          <span class="file-stats">#{killed_count} killed / #{survived_count} survived / #{total} total</span>
        </h2>
        <div class="mutation-map">#{map_html}</div>
        #{build_survived_details(survived)}
      </section>
    HTML
  end

  def build_mutation_map(results)
    results
      .sort_by { |r| r.mutation.line }
      .map { |r| build_map_entry(r) }
      .join("\n")
  end

  def build_map_entry(result)
    mutation = result.mutation
    status = result.status.to_s
    title_attr = result.error_message ? %( title="#{h(result.error_message)}") : ""
    <<~HTML.chomp
      <div class="map-line #{status}"#{title_attr}>
        <span class="line-number">line #{mutation.line}</span>
        <span class="operator">#{h(mutation.operator_name)}</span>
        <span class="status-badge #{status}">#{status}</span>
      </div>
    HTML
  end

  def build_survived_details(survived)
    return "" if survived.empty?

    gaps = Evilution::Result::CoverageGapGrouper.new.call(survived)
    entries = gaps.map { |gap| build_gap_entry(gap) }.join("\n")
    <<~HTML
      <div class="survived-details">
        <h3>Coverage Gaps (#{gaps.length})</h3>
        #{entries}
      </div>
    HTML
  end

  def build_gap_entry(gap)
    if gap.single?
      build_survived_entry(gap.mutation_results.first)
    else
      build_grouped_gap_entry(gap)
    end
  end

  def build_grouped_gap_entry(gap)
    operator_tags = gap.operator_names.map { |op| %(<span class="operator-tag">#{h(op)}</span>) }.join(" ")
    entries_html = gap.mutation_results.map { |r| build_survived_entry(r) }.join("\n")
    <<~HTML
      <div class="coverage-gap">
        <div class="gap-header">
          <span class="location">#{h(gap.file_path)}:#{gap.line} (#{h(gap.subject_name)})</span>
          <span class="gap-count">#{gap.count} mutations</span>
          #{operator_tags}
        </div>
        #{entries_html}
      </div>
    HTML
  end

  def build_survived_entry(result)
    mutation = result.mutation
    suggestion_text = @suggestion.suggestion_for(mutation)
    diff_html = format_diff(mutation.diff)
    regression = regression?(mutation)
    entry_class = regression ? "survived-entry regression" : "survived-entry"
    regression_badge = regression ? ' <span class="regression-badge">NEW REGRESSION</span>' : ""
    <<~HTML
      <div class="#{entry_class}">
        <div class="survived-header">
          <span class="operator">#{h(mutation.operator_name)}#{regression_badge}</span>
          <span class="location">#{h(mutation.file_path)}:#{mutation.line}</span>
        </div>
        <pre class="diff">#{diff_html}</pre>
        <div class="suggestion">#{h(suggestion_text)}</div>
      </div>
    HTML
  end

  def format_diff(diff)
    diff.split("\n").map do |line|
      escaped = h(line)
      css_class = if line.start_with?("- ")
                    "diff-removed"
                  elsif line.start_with?("+ ")
                    "diff-added"
                  else
                    ""
                  end
      %(<span class="#{css_class}">#{escaped}</span>)
    end.join("\n")
  end

  def build_footer
    "<footer>Generated by Evilution v#{h(Evilution::VERSION)}</footer>"
  end

  def score_css_class(score)
    if score >= 0.8
      "score-high"
    elsif score >= 0.5
      "score-medium"
    else
      "score-low"
    end
  end

  def build_baseline_comparison(summary)
    return "" unless @baseline

    base_summary = @baseline["summary"] || {}
    base_score = base_summary["score"] || 0.0
    head_score = summary.score
    delta = head_score - base_score
    delta_str = format("%+.2f%%", delta * 100)
    delta_class = if delta.positive?
                    "delta-positive"
                  elsif delta.negative?
                    "delta-negative"
                  else
                    "delta-neutral"
                  end

    <<~HTML
      <section class="baseline-comparison">
        <h2>Baseline Comparison</h2>
        <div class="comparison-scores">
          <span>Baseline: #{format("%.2f%%", base_score * 100)}</span>
          <span>Current: #{format("%.2f%%", head_score * 100)}</span>
          <span class="#{delta_class}">Delta: #{delta_str}</span>
        </div>
      </section>
    HTML
  end

  def regression?(mutation)
    return false if @baseline_keys.nil?

    key = [mutation.operator_name, mutation.file_path, mutation.line, mutation.subject.name]
    !@baseline_keys.include?(key)
  end

  def build_baseline_keys(baseline)
    return nil unless baseline

    survived = baseline["survived"] || []
    survived.to_set { |m| [m["operator"], m["file"], m["line"], m["subject"]] }
  end

  def h(text)
    CGI.escapeHTML(text.to_s)
  end

  def stylesheet
    <<~HTML
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0d1117; color: #c9d1d9; padding: 2rem; max-width: 1200px; margin: 0 auto; }
        header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; }
        h1 { font-size: 1.5rem; color: #f0f6fc; }
        .version { color: #8b949e; font-weight: normal; font-size: 0.9rem; }
        .score-badge { font-size: 1.8rem; font-weight: bold; padding: 0.3rem 1rem; border-radius: 8px; }
        .score-high { background: #1a4731; color: #3fb950; }
        .score-medium { background: #4a3a10; color: #d29922; }
        .score-low { background: #4a1a1a; color: #f85149; }
        .summary-cards { display: flex; gap: 1rem; flex-wrap: wrap; margin-bottom: 2rem; }
        .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 1rem 1.2rem; text-align: center; min-width: 100px; }
        .card-value { display: block; font-size: 1.4rem; font-weight: bold; color: #f0f6fc; }
        .card-label { display: block; font-size: 0.75rem; color: #8b949e; margin-top: 0.2rem; text-transform: uppercase; }
        .card-killed { border-color: #238636; }
        .card-survived { border-color: #da3633; }
        .truncation-notice { background: #4a3a10; border: 1px solid #d29922; color: #d29922; padding: 0.75rem 1rem; border-radius: 8px; margin-bottom: 2rem; }
        .file-section { background: #161b22; border: 1px solid #30363d; border-radius: 8px; margin-bottom: 1.5rem; overflow: hidden; }
        .file-header { display: flex; justify-content: space-between; align-items: center; padding: 0.75rem 1rem; background: #1c2129; border-bottom: 1px solid #30363d; font-size: 0.9rem; }
        .file-path { color: #58a6ff; font-family: monospace; }
        .file-stats { color: #8b949e; font-size: 0.8rem; font-weight: normal; }
        .mutation-map { padding: 0.5rem 1rem; }
        .map-line { display: flex; align-items: center; gap: 0.75rem; padding: 0.25rem 0.5rem; border-radius: 4px; font-size: 0.85rem; font-family: monospace; }
        .map-line.killed { color: #3fb950; }
        .map-line.survived { color: #f85149; }
        .map-line.timeout { color: #d29922; }
        .map-line.error { color: #f85149; }
        .map-line.neutral { color: #8b949e; }
        .map-line.equivalent { color: #8b949e; }
        .line-number { min-width: 60px; color: #8b949e; }
        .operator { flex: 1; }
        .status-badge { font-size: 0.7rem; padding: 0.1rem 0.5rem; border-radius: 10px; text-transform: uppercase; font-weight: bold; }
        .status-badge.killed { background: #1a4731; }
        .status-badge.survived { background: #4a1a1a; }
        .status-badge.timeout { background: #4a3a10; }
        .status-badge.neutral { background: #21262d; }
        .status-badge.equivalent { background: #21262d; }
        .survived-details { border-top: 1px solid #30363d; padding: 1rem; }
        .survived-details h3 { color: #f85149; font-size: 0.9rem; margin-bottom: 0.75rem; }
        .survived-entry { background: #1c1a1a; border: 1px solid #4a1a1a; border-radius: 6px; padding: 0.75rem; margin-bottom: 0.75rem; }
        .survived-header { display: flex; justify-content: space-between; margin-bottom: 0.5rem; font-size: 0.85rem; }
        .survived-header .operator { color: #f85149; font-weight: bold; }
        .survived-header .location { color: #8b949e; font-family: monospace; }
        .diff { background: #0d1117; border-radius: 4px; padding: 0.5rem 0.75rem; font-size: 0.8rem; overflow-x: auto; line-height: 1.5; }
        .diff-removed { color: #f85149; display: block; }
        .diff-added { color: #3fb950; display: block; }
        .suggestion { color: #d29922; font-size: 0.8rem; margin-top: 0.5rem; font-style: italic; }
        .coverage-gap { border: 1px solid #30363d; border-radius: 6px; padding: 0.75rem; margin-bottom: 0.75rem; background: #161b22; }
        .gap-header { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.5rem; font-size: 0.85rem; padding-bottom: 0.5rem; border-bottom: 1px solid #21262d; }
        .gap-header .location { color: #58a6ff; font-family: monospace; }
        .gap-count { background: #4a1a1a; color: #f85149; font-size: 0.7rem; padding: 0.1rem 0.5rem; border-radius: 10px; font-weight: bold; }
        .operator-tag { background: #21262d; color: #8b949e; font-size: 0.7rem; padding: 0.1rem 0.4rem; border-radius: 4px; font-family: monospace; }
        .empty { color: #8b949e; text-align: center; padding: 2rem; }
        .baseline-comparison { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 1rem; margin-bottom: 2rem; }
        .baseline-comparison h2 { font-size: 1rem; color: #f0f6fc; margin-bottom: 0.75rem; }
        .comparison-scores { display: flex; gap: 2rem; font-size: 0.9rem; }
        .delta-positive { color: #3fb950; font-weight: bold; }
        .delta-negative { color: #f85149; font-weight: bold; }
        .delta-neutral { color: #8b949e; font-weight: bold; }
        .survived-entry.regression { border-color: #f85149; background: #2a1010; }
        .regression-badge { background: #da3633; color: #fff; font-size: 0.65rem; padding: 0.1rem 0.4rem; border-radius: 4px; margin-left: 0.5rem; text-transform: uppercase; font-weight: bold; }
        footer { text-align: center; color: #484f58; font-size: 0.75rem; margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #21262d; }
      </style>
    HTML
  end
end
