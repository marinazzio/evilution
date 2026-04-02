# frozen_string_literal: true

RSpec.describe Evilution::DisableComment do
  subject(:detector) { described_class.new }

  let(:fixture_path) { File.expand_path("../support/fixtures/disable_comments.rb", __dir__) }
  let(:fixture_source) { File.read(fixture_path) }

  describe "#call" do
    it "returns an array of disabled ranges" do
      result = detector.call(fixture_source)

      expect(result).to be_an(Array)
      expect(result).to all(be_a(Range))
    end

    context "with method-level disable" do
      let(:source) do
        <<~RUBY
          # evilution:disable
          def foo
            1 + 2
          end
        RUBY
      end

      it "disables the entire method following the comment" do
        result = detector.call(source)

        expect(result).to include(1..4)
      end
    end

    context "with line-level disable" do
      let(:source) do
        <<~RUBY
          def foo
            x = 1 # evilution:disable
            y = 2
          end
        RUBY
      end

      it "disables only the annotated line" do
        result = detector.call(source)

        expect(result).to eq([2..2])
      end
    end

    context "with range disable/enable pair" do
      let(:source) do
        <<~RUBY
          def foo
            # evilution:disable
            a = dangerous_call
            b = another_call
            # evilution:enable
            a + b
          end
        RUBY
      end

      it "disables lines between disable and enable comments" do
        result = detector.call(source)

        expect(result).to eq([2..5])
      end
    end

    context "with unclosed range" do
      let(:source) do
        <<~RUBY
          def foo
            # evilution:disable
            forever_disabled
          end
        RUBY
      end

      it "extends the range to end of file" do
        result = detector.call(source)

        expect(result).to eq([2..4])
      end
    end

    context "with method-level disable before class method" do
      let(:source) do
        <<~RUBY
          class Foo
            # evilution:disable
            def self.bar
              "skipped"
            end
          end
        RUBY
      end

      it "disables the class method" do
        result = detector.call(source)

        expect(result).to include(2..5)
      end
    end

    context "with multiple disable forms" do
      let(:source) do
        <<~RUBY
          # evilution:disable
          def disabled_method
            "skipped"
          end

          def normal_method
            x = 1 # evilution:disable
            y = 2
          end

          # evilution:disable
          a = 1
          b = 2
          # evilution:enable
        RUBY
      end

      it "returns all disabled ranges" do
        result = detector.call(source)

        expect(result).to contain_exactly(1..4, 7..7, 11..14)
      end
    end

    context "with no disable comments" do
      let(:source) do
        <<~RUBY
          def foo
            1 + 2
          end
        RUBY
      end

      it "returns an empty array" do
        result = detector.call(source)

        expect(result).to eq([])
      end
    end

    context "with empty source" do
      it "returns an empty array" do
        result = detector.call("")

        expect(result).to eq([])
      end
    end

    context "with disable comment inside a string" do
      let(:source) do
        <<~RUBY
          def foo
            "# evilution:disable"
          end
        RUBY
      end

      it "ignores comments inside strings" do
        result = detector.call(source)

        expect(result).to eq([])
      end
    end

    context "with nested range inside method-level disable" do
      let(:source) do
        <<~RUBY
          # evilution:disable
          def foo
            # evilution:disable
            inner
            # evilution:enable
          end
        RUBY
      end

      it "handles the method-level disable covering the whole method" do
        result = detector.call(source)

        expect(result).to include(1..6)
      end
    end

    context "with disable comment with extra whitespace" do
      let(:source) do
        <<~RUBY
          def foo
            x = 1 #   evilution:disable
          end
        RUBY
      end

      it "matches with extra whitespace after #" do
        result = detector.call(source)

        expect(result).to eq([2..2])
      end
    end
  end
end
