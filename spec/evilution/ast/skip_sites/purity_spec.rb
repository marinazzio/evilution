# frozen_string_literal: true

require "spec_helper"
require "evilution/ast/skip_sites/purity"

RSpec.describe Evilution::AST::SkipSites::Purity do
  # Parsed where these names are local variables; any other bare name is a
  # method call.
  def expression(code)
    locals = %i[a b c x y z n k record list opts error path items queue io enum counter sink]
    Prism.parse(code, scopes: [locals]).value.statements.body.first
  end

  [
    '"text"', %("a \#{b} \#{@c} \#{@@d} \#{$e} \#{F::G}"), '"#@a"', ":sym", %(:"s\#{a}"), "/re/", "1 + 2.0", "1r", "2i",
    "nil", "true", "false", "self", "[a, { k: b }]", "opts[k: 1]", "x ? y : z", "a unless b", "a && b || c",
    "record.id", "record.name.inspect", "opts[:key]", 'format("%s", a)', 'sprintf("%s", a)', "list.join(', ')",
    "n.to_s(16)", "a == b", "a != b", "a - b", "a * b", "a / b", "a % b", "a ** b", "a < b", "a > b", "a <= b",
    "a >= b", "a <=> b", "!a", "-a", "defined?(Foo)", "(a)", "__FILE__", "__LINE__", "__ENCODING__", "$1", "$&",
    "1..n", "error.message", "list.empty?", "~a", "+a", "path.basename", "name", "valid?"
  ].each do |code|
    it "treats #{code} as only reading" do
      expect(described_class.pure?(expression(code))).to be true
    end
  end

  [
    "queue.pop!", "record.name = 1", "save(record)", "items.map { |i| i }", "items.each(&:save)",
    "@last = 1", "`ls`", "yield", "super", "->(x) { x }", "a.b(c)",
    "queue.pop", "list.shift", "io.read", "enum.next", "counter.increment", "next_id",
    'name("checkout")', "list.count { |i| i }", "list.any?(&:save)"
  ].each do |code|
    it "treats #{code} as possibly changing state" do
      expect(described_class.pure?(expression(code))).to be false
    end
  end

  %w[
    class name message full_message inspect to_s to_str to_sym to_i to_f to_a to_h id object_id hash size length
    count first last keys values key value path basename dirname extname upcase downcase strip itself
  ].each do |reader|
    it "treats the reader record.#{reader} as only reading" do
      expect(described_class.pure?(expression("record.#{reader}"))).to be true
    end
  end

  it "treats a block given as the root as only reading when its body does" do
    block = expression("f { |a| a }").block

    expect(described_class.pure?(block)).to be true
  end

  it "treats a block whose body may change state as such" do
    expect(described_class.pure?(expression("f { |a| a.save! }").block)).to be false
  end

  it "looks inside nested expressions" do
    expect(described_class.pure?(expression(%("left: \#{[a, queue.pop!].first}")))).to be false
  end
end
