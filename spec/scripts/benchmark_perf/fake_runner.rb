# frozen_string_literal: true

# Stands in for BenchmarkPerf::CommandRunner: records every command and answers
# from a block ([stdout, stderr, success]) so specs can fail chosen commands.
class BenchmarkPerfFakeRunner
  attr_reader :calls

  def initialize(&responder)
    @calls = []
    @responder = responder || ->(_cmd) { ["", "", true] }
  end

  def call(cmd, dir:, env: {})
    @calls << { cmd: cmd, dir: dir, env: env }
    @responder.call(cmd)
  end
end
