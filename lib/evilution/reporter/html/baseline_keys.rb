# frozen_string_literal: true

require_relative "namespace"

class Evilution::Reporter::HTML::BaselineKeys
  def initialize(baseline)
    @keys = build(baseline)
  end

  def regression?(mutation)
    return false if @keys.nil?

    !@keys.include?(key_for(mutation))
  end

  private

  def build(baseline)
    return nil unless baseline

    survived = baseline["survived"] || []
    survived.to_set { |m| [m["operator"], m["file"], m["line"], m["subject"]] }
  end

  def key_for(mutation)
    [mutation.operator_name, mutation.file_path, mutation.line, mutation.subject.name]
  end
end
