# frozen_string_literal: true

require_relative "../sections"

class Evilution::Reporter::HTML::Sections::MutationMap < Evilution::Reporter::HTML::Section
  template "mutation_map"

  Entry = Struct.new(:line, :operator_name, :status, :title_attr)

  def initialize(results)
    @results = results
  end

  private

  def entries
    @entries ||= @results.sort_by { |r| r.mutation.line }.map { |r| build_entry(r) }
  end

  def build_entry(result)
    title = normalize_title(result.error_message)
    title_attr = title ? %( title="#{h(title)}") : ""
    Entry.new(result.mutation.line, result.mutation.operator_name, result.status.to_s, title_attr)
  end

  def normalize_title(message)
    return nil if message.nil?

    normalized = message.gsub(/\s+/, " ").strip
    normalized.empty? ? nil : normalized
  end
end
