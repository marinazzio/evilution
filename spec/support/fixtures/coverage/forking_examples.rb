# frozen_string_literal: true

require_relative "ledger"

# Calls refund only in a process it forks, whose line counts the build that
# forked it never sees.
RSpec.describe CovFixtureLedger do
  it "refunds in a forked process" do
    read, write = IO.pipe
    pid = fork do
      read.close
      ledger = described_class.new
      ledger.refund(5)
      write.write(ledger.total.to_s)
      write.close
      exit!(0)
    end
    write.close
    Process.wait(pid)

    expect(read.read).to eq("-5")
  end
end
