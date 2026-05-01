# frozen_string_literal: true

require "digest"
require_relative "../compare"
require_relative "line_normalizer"

module Evilution::Compare::Fingerprint
  module_function

  def extract_from_evilution_diff(diff)
    minus = []
    plus = []
    diff.to_s.each_line do |line|
      line = line.chomp
      if line.start_with?("- ")
        minus << line[2..]
      elsif line.start_with?("+ ")
        plus << line[2..]
      end
    end
    { minus: minus, plus: plus }
  end

  def extract_from_mutant_diff(diff)
    minus = []
    plus = []
    diff.to_s.each_line do |line|
      line = line.chomp
      next if line.start_with?("---", "+++", "@@")

      if line.start_with?("-")
        minus << line[1..]
      elsif line.start_with?("+")
        plus << line[1..]
      end
    end
    { minus: minus, plus: plus }
  end

  def normalize_line(line)
    Evilution::Compare::LineNormalizer.new.call(line)
  end

  def compute(file_path:, line:, body:)
    normalizer = Evilution::Compare::LineNormalizer.new
    minus = body[:minus].map { |l| normalizer.call(l) }
    plus  = body[:plus].map  { |l| normalizer.call(l) }
    payload = [file_path, line.to_s, minus.join("\n"), plus.join("\n")].join("\x00")
    Digest::SHA256.hexdigest(payload)
  end
end
