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
