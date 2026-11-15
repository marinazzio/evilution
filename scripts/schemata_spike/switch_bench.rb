# frozen_string_literal: true

# Per-call cost of the schemata switch: a plain method against the same
# method in the shape schemata.rb generates, switched on a global and on a
# frozen array slot. The bodies copy the generated code, including its
# redundant `begin`s, the no-op `x * 1` mutant and the repeated original in
# `else`, so the cops that object to that shape (and to three classes in one
# file) are off for it.
# rubocop:disable Style/GlobalVars, Style/RedundantBegin, Lint/UselessNumericOperation, Lint/DuplicateBranch, Style/OneClassPerFile
require "benchmark"

$sw = nil

class Plain
  def f(x) = x + 1
end

class Meta
  def f(x)
    case $sw
    when nil then begin
      x + 1
    end
    when 1 then begin
      x - 1
    end
    when 2 then begin
      x * 1
    end
    else begin
      x + 1
    end
    end
  end
end

SW = [nil].freeze

class MetaConst
  def f(x)
    case SW[0]
    when nil then begin
      x + 1
    end
    when 1 then begin
      x - 1
    end
    else begin
      x + 1
    end
    end
  end
end
# rubocop:enable Style/GlobalVars, Style/RedundantBegin, Lint/UselessNumericOperation, Lint/DuplicateBranch, Style/OneClassPerFile

n = 20_000_000
[Plain, Meta, MetaConst].each do |k|
  o = k.new
  o.f(1)
  t = Benchmark.realtime do
    i = 0
    while i < n
      o.f(i)
      i += 1
    end
  end
  printf("%<name>-10s %<ns>.2f ns/call\n", name: k, ns: t / n * 1e9)
end
