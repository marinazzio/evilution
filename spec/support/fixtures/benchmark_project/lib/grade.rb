# frozen_string_literal: true

module Grade
  module_function

  def letter(score)
    case score
    when 90.. then "A"
    when 80...90 then "B"
    when 70...80 then "C"
    when 60...70 then "D"
    else "F"
    end
  end

  def passed?(score)
    score >= 60 && score <= 100
  end

  def average(scores)
    return nil if scores.empty?

    (scores.sum.to_f / scores.size).round(1)
  end
end
