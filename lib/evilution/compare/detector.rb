# frozen_string_literal: true

require_relative "../compare"
require_relative "normalizer"

module Evilution::Compare::Detector
  module_function

  def call(json)
    raise Evilution::Compare::InvalidInput, "expected Hash, got #{json.class}" unless json.is_a?(Hash)

    mutant = json.key?("subject_results")
    evilution = json.key?("summary") && Evilution::Compare::Normalizer::EVILUTION_BUCKETS.any? { |k| json.key?(k) }

    raise Evilution::Compare::InvalidInput, "ambiguous JSON shape - both mutant and evilution markers present" if mutant && evilution
    return :mutant if mutant
    return :evilution if evilution

    raise Evilution::Compare::InvalidInput, "cannot detect tool from JSON shape"
  end
end
