# frozen_string_literal: true

require_relative "../item_formatters"
require_relative "../pct"

# One line per subject, under its file's heading: what the method scored and
# what that score is made of.
#
# A subject nothing reached says so rather than showing a bare 0.00%, which
# would read like a method whose mutations all survived (EV-nlx1 / GH #1605).
class Evilution::Reporter::CLI::ItemFormatters::SubjectScore
  UNREACHED_NOTE = "nothing reached this subject"

  def initialize(pct: Evilution::Reporter::CLI::Pct.new)
    @pct = pct
  end

  def format(score)
    "    #{method_name(score.name)}  #{@pct.format(score.score)}  #{counts(score)}#{note(score)}"
  end

  private

  # The file heading already carries the class, so the row keeps the part that
  # tells the subjects apart, separator included: "#label_for", ".build".
  def method_name(name)
    boundary = name.rindex(/[#.]/)
    boundary ? name[boundary..] : name
  end

  # Killed over what got a verdict — except where nothing did, in which case the
  # mutations that exist are the more honest denominator.
  def counts(score)
    return "(0/#{score.total})" unless score.reached?

    "(#{score.killed}/#{score.verified})"
  end

  def note(score)
    score.reached? ? "" : "  #{UNREACHED_NOTE}"
  end
end
