# frozen_string_literal: true

# usage: ruby apply_bench.rb <file> [preload]
# What applying one mutation of <file> costs, step by step: syntax check,
# constant-name parse and eval in a warm parent, then eval and the whole
# MutationApplier as the first thing a freshly forked child does.
require "evilution"

file = File.expand_path(ARGV[0])
require File.expand_path(ARGV[1]) if ARGV[1]
src = File.read(file)

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

def per_call_ms(n = 50, &)
  s = now
  n.times(&)
  (now - s) / n * 1000
end

# Median ms of the block run once in each of 20 fresh fork children.
def child_median_ms(&block)
  r, w = IO.pipe
  times = Array.new(20) do
    pid = fork do
      r.close
      s = now
      block.call
      w.write([now - s].pack("E"))
      exit!(0)
    end
    Process.wait(pid)
    r.read(8).unpack1("E") * 1000
  end
  times.sort[10]
end

# Re-evaluating the file is what is being measured; it is the file under test.
evaluate = -> { eval(src, TOPLEVEL_BINDING, file, 1) } # rubocop:disable Security/Eval

$VERBOSE = nil
puts "bytes=#{src.bytesize}"
puts format("syntax_check    %.3f ms", per_call_ms { Evilution::AST::SyntaxCheck.valid?(src) })
puts format("constant_names  %.3f ms", per_call_ms { Evilution::AST::ConstantNames.new.call(src) })
puts format("eval (parent)   %.3f ms", per_call_ms(&evaluate))
puts format("RubyVM compile  %.3f ms", per_call_ms { RubyVM::InstructionSequence.compile(src, file, file, 1) })
puts format("eval (child)    %.3f ms (median)", child_median_ms(&evaluate))

applier = Evilution::Integration::Loading::MutationApplier.new
Mutation = Struct.new(:file_path, :original_source, :eval_source, :mutated_source, keyword_init: true)
mutation = Mutation.new(file_path: file, original_source: src, eval_source: src, mutated_source: src)
puts format("applier (child) %.3f ms (median)", child_median_ms { applier.call(mutation) })
puts format("fork+wait       %.3f ms", per_call_ms(20) { Process.wait(fork { exit!(0) }) })
