# frozen_string_literal: true

require_relative "../line_formatters"

# EV-j0bv / GH #1607: parallel workers contending on shared infrastructure — a
# database file, a lock — crash the test process in a way that says nothing
# about the mutation. Those mutations are re-run serially once the pool is
# done, and the run says so, because the alternative is a neutral count that
# moves with --jobs on identical input with no explanation.
class Evilution::Reporter::CLI::LineFormatters::InfraRetryNotice
  def format(summary)
    count = summary.infra_retried
    return nil if count.zero?

    noun = count == 1 ? "mutation" : "mutations"
    "! #{count} #{noun} hit infrastructure errors under parallel workers; re-ran them serially."
  end
end
