# frozen_string_literal: true

# Records prepare calls; tree path is the ref itself so commands identify the version.
class BenchmarkPerfFakeWorkspace
  attr_reader :prepared

  def initialize(fail_on: nil)
    @prepared = []
    @fail_on = fail_on
  end

  def prepare(target, ref)
    raise BenchmarkPerf::ConfigError, "unknown ref #{ref}" if ref == @fail_on

    @prepared << [target.name, ref]
    "#{target.dir}/Gemfile.benchmark_perf.#{ref}"
  end

  def tree_for(ref)
    "/trees/#{ref}"
  end
end
