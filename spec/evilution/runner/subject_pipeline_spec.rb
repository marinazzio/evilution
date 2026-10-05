# frozen_string_literal: true

require "tmpdir"
require "evilution/config"
require "evilution/ast/parser"
require "evilution/runner/subject_pipeline"

RSpec.describe Evilution::Runner::SubjectPipeline do
  let(:parser) { Evilution::AST::Parser.new }

  def write(dir, rel, source)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  describe "#call with explicit target_files" do
    it "parses subjects from each file" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/foo.rb", <<~RUBY)
          class Foo
            def bar
              1 + 1
            end

            def baz
              2 + 2
            end
          end
        RUBY

        config = Evilution::Config.new(
          target_files: [file], quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)

        subjects = pipeline.call
        expect(subjects.map(&:name)).to contain_exactly("Foo#bar", "Foo#baz")
      end
    end

    it "exposes the resolved target_files for reuse" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/foo.rb", "class Foo; def bar; end; end\n")
        config = Evilution::Config.new(
          target_files: [file], quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)

        expect(pipeline.target_files).to eq([file])
      end
    end
  end

  describe "#call with source: glob target" do
    it "returns subjects from glob-matched files sorted by path" do
      Dir.mktmpdir do |dir|
        write(dir, "lib/a.rb", "class A; def x; end; end\n")
        write(dir, "lib/b.rb", "class B; def y; end; end\n")

        Dir.chdir(dir) do
          config = Evilution::Config.new(
            target: "source:lib/*.rb", quiet: true, baseline: false, skip_config_file: true
          )
          pipeline = described_class.new(config, parser: parser)
          expect(pipeline.call.map(&:name)).to eq(%w[A#x B#y])
        end
      end
    end

    it "sorts glob results that arrive out of order" do
      Dir.mktmpdir do |dir|
        a = write(dir, "lib/a.rb", "class A; def x; end; end\n")
        b = write(dir, "lib/b.rb", "class B; def y; end; end\n")
        allow(Dir).to receive(:glob).and_return([b, a])

        config = Evilution::Config.new(
          target: "source:lib/*.rb", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to eq(%w[A#x B#y])
      end
    end

    it "raises Evilution::Error when the glob matches nothing" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          config = Evilution::Config.new(
            target: "source:lib/nothing/*.rb", quiet: true, baseline: false, skip_config_file: true
          )
          pipeline = described_class.new(config, parser: parser)
          expect { pipeline.call }.to raise_error(Evilution::Error, /no files found/)
        end
      end
    end
  end

  describe "#call with method target" do
    let(:fixture) do
      <<~RUBY
        class Foo
          def bar; 1; end
          def baz; 2; end
        end
        class Food
          def fry; 3; end
        end
      RUBY
    end

    it "matches an exact Class#method target" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/foo.rb", fixture)
        config = Evilution::Config.new(
          target_files: [file], target: "Foo#bar", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to eq(["Foo#bar"])
      end
    end

    it "matches a constant subject by its exact name" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/geo.rb", "module Geo\n  Point = Data.define(:x, :y)\n  def self.origin = 0\nend\n")
        config = Evilution::Config.new(
          target_files: [file], target: "Geo::Point", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to eq(["Geo::Point"])
      end
    end

    it "matches the methods and the constant subject of a class by its name" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/coord.rb", "class Coord < Data.define(:lat)\n  def north? = lat.positive?\nend\n")
        config = Evilution::Config.new(
          target_files: [file], target: "Coord", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to eq(["Coord", "Coord#north?"])
      end
    end

    it "matches a trailing-hash prefix target" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/foo.rb", fixture)
        config = Evilution::Config.new(
          target_files: [file], target: "Foo#", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to contain_exactly("Foo#bar", "Foo#baz")
      end
    end

    it "matches a wildcard class-name target" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/foo.rb", fixture)
        config = Evilution::Config.new(
          target_files: [file], target: "Foo*", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to contain_exactly("Foo#bar", "Foo#baz", "Food#fry")
      end
    end

    it "excludes subjects whose class name does not start with the wildcard prefix" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/mixed.rb", <<~RUBY)
          class Foo
            def bar; 1; end
          end
          class Bar
            def qux; 2; end
          end
        RUBY
        config = Evilution::Config.new(
          target_files: [file], target: "Foo*", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to eq(["Foo#bar"])
      end
    end

    it "matches bare class name to both instance and class methods" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/foo.rb", <<~RUBY)
          class Foo
            def bar; 1; end
            def self.baz; 2; end
          end
        RUBY
        config = Evilution::Config.new(
          target_files: [file], target: "Foo", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to contain_exactly("Foo#bar", "Foo.baz")
      end
    end

    it "matches a bare class name exactly, not as a name prefix" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/foo.rb", fixture)
        config = Evilution::Config.new(
          target_files: [file], target: "Foo", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to contain_exactly("Foo#bar", "Foo#baz")
      end
    end

    it "raises Evilution::Error when no subject matches with explicit files" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/foo.rb", fixture)
        config = Evilution::Config.new(
          target_files: [file], target: "Nope#gone", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect { pipeline.call }.to raise_error(Evilution::Error, /no subject matched 'Nope#gone'/)
      end
    end

    it "does not include the git-changed hint when file scope was explicit" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/foo.rb", fixture)
        config = Evilution::Config.new(
          target_files: [file], target: "Nope#gone", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect { pipeline.call }.to raise_error(Evilution::Error) { |e|
          expect(e.message).not_to match(/git-changed/)
        }
      end
    end

    it "raises with a git-changed-files hint when fallback returned empty" do
      changed = instance_double(Evilution::Git::ChangedFiles, call: [])
      allow(Evilution::Git::ChangedFiles).to receive(:new).and_return(changed)

      config = Evilution::Config.new(
        target: "Foo::Bar", quiet: true, baseline: false, skip_config_file: true
      )
      pipeline = described_class.new(config, parser: parser)

      expect { pipeline.call }.to raise_error(
        Evilution::Error,
        /no subject matched 'Foo::Bar'.*git-changed files.*source:/m
      )
    end

    it "raises with a git-changed-files hint when fallback files lack the target class" do
      Dir.mktmpdir do |dir|
        unrelated = write(dir, "lib/unrelated.rb", "class Unrelated; def x; end; end\n")
        changed = instance_double(Evilution::Git::ChangedFiles, call: [unrelated])
        allow(Evilution::Git::ChangedFiles).to receive(:new).and_return(changed)

        config = Evilution::Config.new(
          target: "PgObjects::Manager", quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)

        expect { pipeline.call }.to raise_error(
          Evilution::Error,
          /no subject matched 'PgObjects::Manager'.*git-changed files/m
        )
      end
    end
  end

  describe "#call with descendants: target" do
    let(:fixture) do
      <<~RUBY
        class Base
          def a; end
        end
        class Child < Base
          def b; end
        end
        class Grandchild < Child
          def c; end
        end
        class Unrelated
          def d; end
        end
      RUBY
    end

    it "includes the base and all transitive descendants" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/tree.rb", fixture)
        config = Evilution::Config.new(
          target_files: [file], target: "descendants:Base",
          quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to contain_exactly("Base#a", "Child#b", "Grandchild#c")
      end
    end

    it "raises Evilution::Error for an unknown base class" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/tree.rb", fixture)
        config = Evilution::Config.new(
          target_files: [file], target: "descendants:Missing",
          quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect { pipeline.call }.to raise_error(Evilution::Error, /no classes found/)
      end
    end

    it "names the unmatched target in the no-classes-found error" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/tree.rb", fixture)
        config = Evilution::Config.new(
          target_files: [file], target: "descendants:Missing",
          quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect { pipeline.call }
          .to raise_error(Evilution::Error, /matching 'descendants:Missing'/)
      end
    end

    it "follows the inheritance chain even when classes are declared child-first" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/tree.rb", <<~RUBY)
          class Grandchild < Child
            def c; end
          end
          class Child < Base
            def b; end
          end
          class Base
            def a; end
          end
        RUBY
        config = Evilution::Config.new(
          target_files: [file], target: "descendants:Base",
          quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to contain_exactly("Base#a", "Child#b", "Grandchild#c")
      end
    end
  end

  describe "#call with line_ranges" do
    it "keeps subjects whose lines overlap the configured range" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/foo.rb", <<~RUBY)
          class Foo
            def a       # line 2
              1
            end

            def b       # line 6
              2
            end

            def c       # line 10
              3
            end
          end
        RUBY

        config = Evilution::Config.new(
          target_files: [file], line_ranges: { file => (5..7) },
          quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to eq(["Foo#b"])
      end
    end

    it "keeps all subjects from files that have no configured range" do
      Dir.mktmpdir do |dir|
        ranged = write(dir, "lib/ranged.rb", <<~RUBY)
          class Ranged
            def keep       # line 2
              1
            end
          end
        RUBY
        unranged = write(dir, "lib/unranged.rb", "class Other; def kept; end; end\n")

        config = Evilution::Config.new(
          target_files: [ranged, unranged], line_ranges: { ranged => (1..4) },
          quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to contain_exactly("Ranged#keep", "Other#kept")
      end
    end

    it "keeps a multi-line subject whose body reaches into the range" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/big.rb", <<~RUBY)
          class Foo
            def big       # starts line 2
              a = 1
              b = 2
              c = 3
              d = 4       # line 6
            end
          end
        RUBY

        config = Evilution::Config.new(
          target_files: [file], line_ranges: { file => (6..6) },
          quiet: true, baseline: false, skip_config_file: true
        )
        pipeline = described_class.new(config, parser: parser)
        expect(pipeline.call.map(&:name)).to eq(["Foo#big"])
      end
    end

    context "when the range holds code outside every subject" do
      let(:model_source) do
        <<~RUBY
          class Order
            scope :for_owner, ->(owner) do
              owner ? where(owner: owner) : none
            end

            def total
              1
            end
          end
        RUBY
      end

      it "warns which lines no subject covers" do
        Dir.mktmpdir do |dir|
          file = write(dir, "app/models/order.rb", model_source)
          config = Evilution::Config.new(
            target_files: [file], line_ranges: { file => (2..4) },
            quiet: true, baseline: false, skip_config_file: true
          )
          pipeline = described_class.new(config, parser: parser)

          expect { expect(pipeline.call).to be_empty }
            .to output("[evilution] #{file}:2-4 holds code outside every subject (class-body code such as " \
                       "DSL calls and constants is not mutated); no mutations target those lines.\n").to_stderr
          expect(pipeline.uncovered_code).to eq([{ file: file, lines: ["2-4"] }])
        end
      end

      it "names only the uncovered part of a range that also reaches a method" do
        Dir.mktmpdir do |dir|
          file = write(dir, "app/models/order.rb", model_source)
          config = Evilution::Config.new(
            target_files: [file], line_ranges: { file => (3..7) },
            quiet: true, baseline: false, skip_config_file: true
          )
          pipeline = described_class.new(config, parser: parser)

          expect { expect(pipeline.call.map(&:name)).to eq(["Order#total"]) }
            .to output(/#{Regexp.escape(file)}:3-4 holds code outside every subject/).to_stderr
        end
      end

      it "stays silent when the range holds only methods" do
        Dir.mktmpdir do |dir|
          file = write(dir, "app/models/order.rb", model_source)
          config = Evilution::Config.new(
            target_files: [file], line_ranges: { file => (6..8) },
            quiet: true, baseline: false, skip_config_file: true
          )
          pipeline = described_class.new(config, parser: parser)

          expect { pipeline.call }.not_to output.to_stderr
          expect(pipeline.uncovered_code).to eq([])
        end
      end
    end
  end

  describe "#call with a target file that has no subjects" do
    it "warns which lines hold code no subject covers" do
      Dir.mktmpdir do |dir|
        file = write(dir, "app/models/scopes.rb", <<~RUBY)
          module Scopes
            LIMIT = 10

            private

            ORDER = :asc
          end
        RUBY
        config = Evilution::Config.new(target_files: [file], quiet: true, baseline: false, skip_config_file: true)
        pipeline = described_class.new(config, parser: parser)

        expect { pipeline.call }.to output(/#{Regexp.escape(file)}:2, 6 holds code outside every subject/).to_stderr
        expect(pipeline.uncovered_code).to eq([{ file: file, lines: %w[2 6] }])
      end
    end

    it "does not inspect a whole file that has subjects" do
      Dir.mktmpdir do |dir|
        file = write(dir, "app/models/order.rb", <<~RUBY)
          class Order
            LIMIT = 10

            def total
              1
            end
          end
        RUBY
        config = Evilution::Config.new(target_files: [file], quiet: true, baseline: false, skip_config_file: true)
        pipeline = described_class.new(config, parser: parser)

        expect { pipeline.call }.not_to output.to_stderr
        expect(pipeline.uncovered_code).to eq([])
      end
    end

    it "stays silent for a file with no code" do
      Dir.mktmpdir do |dir|
        file = write(dir, "lib/empty.rb", "# frozen_string_literal: true\n")
        config = Evilution::Config.new(target_files: [file], quiet: true, baseline: false, skip_config_file: true)
        pipeline = described_class.new(config, parser: parser)

        expect { pipeline.call }.not_to output.to_stderr
      end
    end
  end

  describe "#call with no target_files and no target" do
    it "delegates to Git::ChangedFiles" do
      changed = instance_double(Evilution::Git::ChangedFiles, call: [])
      allow(Evilution::Git::ChangedFiles).to receive(:new).and_return(changed)

      config = Evilution::Config.new(
        quiet: true, baseline: false, skip_config_file: true
      )
      pipeline = described_class.new(config, parser: parser)
      expect(pipeline.call).to eq([])
      expect(changed).to have_received(:call)
    end
  end
end
