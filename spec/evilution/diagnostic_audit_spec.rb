# frozen_string_literal: true

require "prism"

# Kernel#warn goes through Warning.warn, which a project may make raise; every
# message evilution writes about itself goes through Evilution::Diagnostic
# instead. Walking the AST rather than grepping keeps interpolated messages and
# multi-line calls in view.
RSpec.describe "Kernel#warn in lib/" do
  lib_root = File.expand_path("../../lib", __dir__)

  finder = Class.new(Prism::Visitor) do
    attr_reader :lines

    def initialize
      super
      @lines = []
    end

    def visit_call_node(node)
      @lines << node.location.start_line if node.name == :warn && node.receiver.nil?
      super
    end
  end

  it "is never called; messages go through Evilution::Diagnostic.warn" do
    offenders = Dir.glob(File.join(lib_root, "**", "*.rb")).flat_map do |path|
      visitor = finder.new
      visitor.visit(Prism.parse_file(path).value)
      visitor.lines.map { |line| "#{path.delete_prefix("#{lib_root}/")}:#{line}" }
    end

    expect(offenders).to be_empty
  end
end
