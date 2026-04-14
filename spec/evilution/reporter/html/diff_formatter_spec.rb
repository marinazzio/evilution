# frozen_string_literal: true

require "evilution/reporter/html/diff_formatter"

RSpec.describe Evilution::Reporter::HTML::DiffFormatter do
  describe ".call" do
    it "wraps removed lines in diff-removed span" do
      html = described_class.call("- x >= 10")
      expect(html).to eq(%(<span class="diff-removed">- x &gt;= 10</span>))
    end

    it "wraps added lines in diff-added span" do
      html = described_class.call("+ x > 10")
      expect(html).to eq(%(<span class="diff-added">+ x &gt; 10</span>))
    end

    it "wraps context lines in an empty-class span" do
      expect(described_class.call("  context")).to eq(%(<span class="">  context</span>))
    end

    it "joins multiple lines with newline" do
      html = described_class.call("- a\n+ b")
      expect(html).to eq(
        %(<span class="diff-removed">- a</span>\n<span class="diff-added">+ b</span>)
      )
    end

    it "escapes HTML in diff content" do
      html = described_class.call("- <script>")
      expect(html).to include("&lt;script&gt;")
    end
  end
end
