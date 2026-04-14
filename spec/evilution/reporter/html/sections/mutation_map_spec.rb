# frozen_string_literal: true

require "evilution/reporter/html/sections/mutation_map"

RSpec.describe Evilution::Reporter::HTML::Sections::MutationMap do
  def result(line:, op: "replace_op", status: :killed, error_message: nil)
    mutation = double("Mutation", line: line, operator_name: op)
    double("Result", mutation: mutation, status: status, error_message: error_message)
  end

  it "renders entries sorted by line number" do
    html = described_class.new([result(line: 10), result(line: 3)]).render
    expect(html.index("line 3")).to be < html.index("line 10")
  end

  it "applies status class to each map line" do
    html = described_class.new([result(line: 1, status: :survived)]).render
    expect(html).to include('class="map-line survived"')
    expect(html).to include('class="status-badge survived">survived')
  end

  it "adds title attribute when error_message is present" do
    html = described_class.new([result(line: 1, status: :error, error_message: "boom")]).render
    expect(html).to include('title="boom"')
  end

  it "omits title attribute when error_message is nil" do
    html = described_class.new([result(line: 1)]).render
    expect(html).not_to include("title=")
  end

  it "collapses whitespace in multi-line error messages" do
    html = described_class.new([result(line: 1, status: :error, error_message: "a\n\n  b")]).render
    expect(html).to include('title="a b"')
  end

  it "escapes HTML in the title attribute" do
    html = described_class.new([result(line: 1, status: :error, error_message: "<script>")]).render
    expect(html).to include('title="&lt;script&gt;"')
  end

  it "escapes HTML in the operator name" do
    html = described_class.new([result(line: 1, op: "<op>")]).render
    expect(html).to include("&lt;op&gt;")
  end
end
