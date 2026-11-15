# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "evilution/git/since_scope"

RSpec.describe Evilution::Git::SinceScope do
  def lines(*ranges)
    Evilution::LineSet.new(ranges)
  end

  def scope(changed, files: [], line_ranges: {})
    described_class.new(changed).call(files: files, line_ranges: line_ranges)
  end

  def in_project(*paths)
    Dir.mktmpdir("since_scope_spec") do |dir|
      Dir.chdir(dir) do
        paths.each do |path|
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, "")
        end
        yield
      end
    end
  end

  describe ".apply" do
    it "leaves the files and ranges as given without a ref" do
      result = described_class.apply(nil, files: ["lib/a.rb"], line_ranges: { "lib/a.rb" => 1..2 })

      expect(result.files).to eq(["lib/a.rb"])
      expect(result.ranges).to eq("lib/a.rb" => 1..2)
    end

    it "narrows the files and ranges given to the lines changed since the ref" do
      in_project("lib/a.rb") do
        changed_lines = instance_double(Evilution::Git::ChangedLines, call: { "lib/a.rb" => lines(4..6) })
        allow(Evilution::Git::ChangedLines).to receive(:new).with("main").and_return(changed_lines)

        result = described_class.apply("main", files: ["lib/a.rb"], line_ranges: { "lib/a.rb" => 5..9 })

        expect(result.ranges).to eq("lib/a.rb" => lines(5..6))
      end
    end

    it "drops a file given that exists and did not change" do
      in_project("lib/a.rb", "lib/b.rb") do
        changed_lines = instance_double(Evilution::Git::ChangedLines, call: { "lib/b.rb" => lines(1..1) })
        allow(Evilution::Git::ChangedLines).to receive(:new).with("main").and_return(changed_lines)

        expect(described_class.apply("main", files: ["lib/a.rb", "lib/b.rb"], line_ranges: {}).files).to eq(["lib/b.rb"])
      end
    end

    it "raises a ConfigError for a file given that does not exist, before git is asked" do
      in_project("lib/a.rb") do
        allow(Evilution::Git::ChangedLines).to receive(:new)

        expect { described_class.apply("main", files: ["lib/a.rb", "lib/aa.rb"], line_ranges: {}) }
          .to raise_error(Evilution::ConfigError, "file not found: lib/aa.rb")
        expect(Evilution::Git::ChangedLines).not_to have_received(:new)
      end
    end

    it "raises a ConfigError for a directory given, before git is asked" do
      in_project("lib/a.rb") do
        allow(Evilution::Git::ChangedLines).to receive(:new)

        expect { described_class.apply("main", files: ["lib/"], line_ranges: {}) }
          .to raise_error(Evilution::ConfigError, %r{\Alib/ is a directory; --since takes files})
        expect(Evilution::Git::ChangedLines).not_to have_received(:new)
      end
    end

    it "does not check the files given without a ref" do
      in_project do
        result = described_class.apply(nil, files: ["lib/missing.rb"], line_ranges: {})

        expect(result.files).to eq(["lib/missing.rb"])
      end
    end

    it "limits them to the lines changed since the ref" do
      changed_lines = instance_double(Evilution::Git::ChangedLines, call: { "lib/a.rb" => lines(4..4) })
      allow(Evilution::Git::ChangedLines).to receive(:new).with("main").and_return(changed_lines)

      result = described_class.apply("main", files: [], line_ranges: {})

      expect(result.files).to eq(["lib/a.rb"])
      expect(result.ranges).to eq("lib/a.rb" => lines(4..4))
    end
  end

  describe "#call without file arguments" do
    it "takes the changed Ruby files under lib/ and app/, sorted, with their changed lines" do
      result = scope({ "lib/b.rb" => lines(3..3), "app/models/a.rb" => lines(1..2), "lib/a.rb" => lines(9..9) })

      expect(result.files).to eq(["app/models/a.rb", "lib/a.rb", "lib/b.rb"])
      expect(result.ranges).to eq(
        "app/models/a.rb" => lines(1..2), "lib/a.rb" => lines(9..9), "lib/b.rb" => lines(3..3)
      )
    end

    it "leaves out specs, tests and files outside lib/ and app/" do
      result = scope({ "spec/a_spec.rb" => lines(1..1), "test/a_test.rb" => lines(1..1), "bin/a.rb" => lines(1..1) })

      expect(result.files).to eq([])
      expect(result.ranges).to eq({})
    end

    it "leaves out files that are not Ruby" do
      changed = { "lib/a.yml" => lines(1..1), "lib/tasks/a.rake" => lines(1..1), "app/views/a.html.erb" => lines(1..1) }
      result = scope(changed)

      expect(result.files).to eq([])
    end

    it "is empty when nothing changed" do
      expect(scope({}).files).to eq([])
    end
  end

  describe "#call with file arguments" do
    it "keeps the files given that changed, with their changed lines" do
      result = scope({ "lib/a.rb" => lines(2..3), "lib/b.rb" => lines(5..5) }, files: ["lib/a.rb", "lib/c.rb"])

      expect(result.files).to eq(["lib/a.rb"])
      expect(result.ranges).to eq("lib/a.rb" => lines(2..3))
    end

    it "keeps a changed file given outside lib/ and app/, or not ending in .rb" do
      changed = { "bin/tool.rb" => lines(1..1), "lib/tasks/a.rake" => lines(2..2) }

      expect(scope(changed, files: ["bin/tool.rb", "lib/tasks/a.rake"]).files).to eq(["bin/tool.rb", "lib/tasks/a.rake"])
    end

    it "keeps the spelling the file was given in" do
      result = scope({ "lib/a.rb" => lines(2..3) }, files: ["./lib/a.rb"])

      expect(result.files).to eq(["./lib/a.rb"])
      expect(result.ranges).to eq("./lib/a.rb" => lines(2..3))
    end

    it "narrows a file's line range to the lines that changed in it" do
      result = scope({ "lib/a.rb" => lines(2..3, 10..12) }, files: ["lib/a.rb"], line_ranges: { "lib/a.rb" => 3..11 })

      expect(result.ranges).to eq("lib/a.rb" => lines(3..3, 10..11))
    end

    it "drops a file none of whose changed lines are in its line range" do
      result = scope({ "lib/a.rb" => lines(2..3) }, files: ["lib/a.rb"], line_ranges: { "lib/a.rb" => 5..9 })

      expect(result.files).to eq([])
      expect(result.ranges).to eq({})
    end

    it "keeps a changed file given after one that did not change" do
      expect(scope({ "lib/b.rb" => lines(1..1) }, files: ["lib/a.rb", "lib/b.rb"]).files).to eq(["lib/b.rb"])
    end

    it "keeps a file given twice once" do
      expect(scope({ "lib/a.rb" => lines(1..1) }, files: ["lib/a.rb", "lib/a.rb"]).files).to eq(["lib/a.rb"])
    end

    it "is empty when none of the files given changed" do
      expect(scope({ "lib/b.rb" => lines(1..1) }, files: ["lib/a.rb"]).files).to eq([])
    end
  end
end
