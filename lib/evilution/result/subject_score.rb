# frozen_string_literal: true

require_relative "../result"

# What one subject — a single method — scored, alongside the counts behind it.
#
# The run's own score is computed per file, so a well-tested file that gains new
# untested methods still reports 100%: whatever the resolved spec reaches is all
# the number ever describes (EV-nlx1 / GH #1605). Per subject the picture
# separates: a method whose mutations were never reached scores nothing and says
# so, instead of disappearing into the file's total.
Evilution::Result::SubjectScore = Data.define(:name, :file_path, :total, :killed, :verified, :survived) do
  # Killed over what actually got a verdict, the same denominator the run uses.
  def score
    return 0.0 if verified.zero?

    killed.to_f / verified
  end

  # Whether any mutation of this subject got a verdict at all.
  def reached?
    verified.positive?
  end

  def fully_verified?
    reached? && killed == verified
  end
end
