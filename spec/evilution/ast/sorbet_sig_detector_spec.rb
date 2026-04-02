# frozen_string_literal: true

RSpec.describe Evilution::AST::SorbetSigDetector do
  subject(:detector) { described_class.new }

  describe "#call" do
    context "with inline sig block" do
      let(:source) do
        <<~RUBY
          class Foo
            sig { returns(Integer) }
            def bar
              42
            end
          end
        RUBY
      end

      it "returns the byte range of the sig block" do
        ranges = detector.call(source)

        expect(ranges.length).to eq(1)
        expect(source.byteslice(ranges.first)).to eq("sig { returns(Integer) }")
      end
    end

    context "with multi-line sig block" do
      let(:source) do
        <<~RUBY
          class Foo
            sig do
              params(
                name: String,
                age: Integer
              ).returns(T::Boolean)
            end
            def bar(name, age)
              true
            end
          end
        RUBY
      end

      it "returns the byte range of the multi-line sig block" do
        ranges = detector.call(source)

        expect(ranges.length).to eq(1)
        expect(source.byteslice(ranges.first)).to start_with("sig do")
        expect(source.byteslice(ranges.first)).to end_with("end")
      end
    end

    context "with multiple sig blocks" do
      let(:source) do
        <<~RUBY
          class Foo
            sig { returns(Integer) }
            def bar
              42
            end

            sig { params(x: String).returns(String) }
            def baz(x)
              x.upcase
            end
          end
        RUBY
      end

      it "returns all sig block ranges" do
        ranges = detector.call(source)

        expect(ranges.length).to eq(2)
        expect(source.byteslice(ranges[0])).to eq("sig { returns(Integer) }")
        expect(source.byteslice(ranges[1])).to eq("sig { params(x: String).returns(String) }")
      end
    end

    context "with no sig blocks" do
      let(:source) do
        <<~RUBY
          class Foo
            def bar
              42
            end
          end
        RUBY
      end

      it "returns an empty array" do
        ranges = detector.call(source)

        expect(ranges).to eq([])
      end
    end

    context "with empty source" do
      it "returns an empty array" do
        expect(detector.call("")).to eq([])
      end
    end

    context "with method named sig that has arguments" do
      let(:source) do
        <<~RUBY
          class Foo
            def test
              sig("not a type signature")
            end
          end
        RUBY
      end

      it "does not match sig calls with arguments" do
        ranges = detector.call(source)

        expect(ranges).to eq([])
      end
    end

    context "with method named sig without a block" do
      let(:source) do
        <<~RUBY
          class Foo
            def test
              sig
            end
          end
        RUBY
      end

      it "does not match sig calls without a block" do
        ranges = detector.call(source)

        expect(ranges).to eq([])
      end
    end

    context "with sig call on a receiver" do
      let(:source) do
        <<~RUBY
          class Foo
            def test
              obj.sig { something }
            end
          end
        RUBY
      end

      it "does not match sig calls with an explicit receiver" do
        ranges = detector.call(source)

        expect(ranges).to eq([])
      end
    end

    context "with parse error" do
      let(:source) { "def foo(" }

      it "returns an empty array" do
        ranges = detector.call(source)

        expect(ranges).to eq([])
      end
    end
  end

  describe "#line_ranges" do
    context "with inline sig block" do
      let(:source) do
        <<~RUBY
          class Foo
            sig { returns(Integer) }
            def bar
              42
            end
          end
        RUBY
      end

      it "returns line ranges of sig blocks" do
        ranges = detector.line_ranges(source)

        expect(ranges).to eq([2..2])
      end
    end

    context "with multi-line sig block" do
      let(:source) do
        <<~RUBY
          class Foo
            sig do
              params(name: String).returns(T::Boolean)
            end
            def bar(name)
              true
            end
          end
        RUBY
      end

      it "returns the full line range of the sig block" do
        ranges = detector.line_ranges(source)

        expect(ranges).to eq([2..4])
      end
    end

    context "with no sig blocks" do
      it "returns an empty array" do
        ranges = detector.line_ranges("def foo; end")

        expect(ranges).to eq([])
      end
    end

    context "with empty source" do
      it "returns an empty array" do
        expect(detector.line_ranges("")).to eq([])
      end
    end
  end
end
