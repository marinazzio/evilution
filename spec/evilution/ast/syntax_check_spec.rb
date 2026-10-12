# frozen_string_literal: true

require "open3"
require "rbconfig"
require "evilution/ast/syntax_check"

RSpec.describe Evilution::AST::SyntaxCheck do
  # Prism accepts a bare constant operator write inside a method; parse.y
  # rejects it as a dynamic constant assignment.
  let(:prism_only_source) { "def f(v); LIMIT ||= v; end\n" }
  let(:valid_source) { "def f(v); @limit ||= v; end\n" }
  let(:invalid_source) { "def f(\n" }

  describe ".valid?" do
    context "when the interpreter compiles with Prism" do
      it "accepts source Prism parses" do
        expect(described_class.valid?(valid_source, prism_interpreter: true)).to be(true)
      end

      it "rejects source Prism does not parse" do
        expect(described_class.valid?(invalid_source, prism_interpreter: true)).to be(false)
      end

      it "accepts source only Prism parses, the interpreter being Prism" do
        expect(described_class.valid?(prism_only_source, prism_interpreter: true)).to be(true)
      end

      it "does not ask parse.y" do
        allow(RubyVM::AbstractSyntaxTree).to receive(:parse)

        described_class.valid?(valid_source, prism_interpreter: true)

        expect(RubyVM::AbstractSyntaxTree).not_to have_received(:parse)
      end
    end

    context "when the interpreter compiles with parse.y" do
      it "accepts source both parsers accept" do
        expect(described_class.valid?(valid_source, prism_interpreter: false)).to be(true)
      end

      it "rejects source Prism does not parse, without asking parse.y" do
        allow(RubyVM::AbstractSyntaxTree).to receive(:parse)

        expect(described_class.valid?(invalid_source, prism_interpreter: false)).to be(false)
        expect(RubyVM::AbstractSyntaxTree).not_to have_received(:parse)
      end

      it "rejects source Prism parses and parse.y does not" do
        expect(described_class.valid?(prism_only_source, prism_interpreter: false)).to be(false)
      end

      it "rejects a pattern only Prism parses" do
        source = "def f(v)\n  return unless v in nil[size: [first]]\n  first\nend\n"

        expect(Prism.parse(source)).to be_success
        expect(described_class.valid?(source, prism_interpreter: false)).to be(false)
      end

      it "keeps the warnings parse.y has about the source to itself" do
        source = "def f(v)\n  v == 1\n  2\nend\n"
        check = lambda do
          previous = $VERBOSE
          $VERBOSE = true
          described_class.valid?(source, prism_interpreter: false)
        ensure
          $VERBOSE = previous
        end

        expect(&check).not_to output.to_stderr
      end

      it "leaves $VERBOSE as it found it" do
        previous = $VERBOSE
        $VERBOSE = true
        described_class.valid?(valid_source, prism_interpreter: false)

        expect($VERBOSE).to be(true)
      ensure
        $VERBOSE = previous
      end

      it "restores $VERBOSE when parse.y rejects the source" do
        previous = $VERBOSE
        $VERBOSE = true
        described_class.valid?(prism_only_source, prism_interpreter: false)

        expect($VERBOSE).to be(true)
      ensure
        $VERBOSE = previous
      end

      it "trusts Prism on a Ruby that has no parse.y to ask" do
        hide_const("RubyVM::AbstractSyntaxTree")

        expect(described_class.valid?(prism_only_source, prism_interpreter: false)).to be(true)
      end

      it "does not reach for parse.y where there is none" do
        hide_const("RubyVM::AbstractSyntaxTree")
        allow(described_class).to receive(:without_warnings).and_call_original

        described_class.valid?(valid_source, prism_interpreter: false)

        expect(described_class).not_to have_received(:without_warnings)
      end

      it "trusts Prism when parse.y fails for a reason other than syntax" do
        allow(RubyVM::AbstractSyntaxTree).to receive(:parse).and_raise(ArgumentError, "invalid byte sequence")

        expect(described_class.valid?(valid_source, prism_interpreter: false)).to be(true)
      end
    end

    it "takes the interpreter's parser from RUBY_DESCRIPTION by default" do
      expect(described_class::PRISM_INTERPRETER).to eq(RUBY_DESCRIPTION.include?("+PRISM"))
      expect(described_class.valid?(prism_only_source)).to eq(described_class::PRISM_INTERPRETER)
    end
  end

  # The check as a parse.y interpreter runs it. Ruby 3.3 compiles with
  # parse.y unless told otherwise; later versions take a flag for it.
  describe "under an interpreter that compiles with parse.y" do
    let(:root) { File.expand_path("../../..", __dir__) }
    let(:parser_flag) { Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.4") ? ["--parser=parse.y"] : [] }

    def run_ruby(script)
      out, err, status = Open3.capture3(RbConfig.ruby, *parser_flag, "-I", File.join(root, "lib"), "-e", script)
      raise "ruby failed: #{err}" unless status.success?

      out.strip
    end

    it "marks a mutation only Prism parses as unparseable" do
      script = <<~RUBY
        require "evilution/ast/source_surgeon"
        source = "def f(v); A::LIMIT ||= v; end\\n"
        result = Evilution::AST::SourceSurgeon.apply(source, offset: 10, length: 3, replacement: "")
        puts [Evilution::AST::SyntaxCheck::PRISM_INTERPRETER, result.source.strip, result.status].inspect
      RUBY

      expect(run_ruby(script)).to eq('[false, "def f(v); LIMIT ||= v; end", :unparseable]')
    end

    it "refuses to apply source only Prism parses" do
      script = <<~RUBY
        require "evilution/integration/loading/syntax_validator"
        result = Evilution::Integration::Loading::SyntaxValidator.new.call("def f(v); LIMIT ||= v; end\\n")
        puts result.fetch(:error_class)
      RUBY

      expect(run_ruby(script)).to eq("SyntaxError")
    end
  end
end
