# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "evilution/git/changed_lines"

RSpec.describe Evilution::Git::ChangedLines do
  # The scratch repositories are set up by these examples alone: the global
  # and system git config (commit signing, hooks, templates) and the GIT_*
  # variables of the shell running the suite would otherwise reach them.
  around do |example|
    saved = ENV.to_h
    ENV.delete_if { |name, _| name.start_with?("GIT_") }
    ENV.update("GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1")
    example.run
  ensure
    ENV.replace(saved)
  end

  def git(*args)
    system("git", *args, out: File::NULL, err: File::NULL) || raise("git #{args.join(" ")} failed")
  end

  def in_git_repo
    Dir.mktmpdir("changed_lines_spec") do |dir|
      Dir.chdir(dir) do
        git("init", "--quiet", "--initial-branch=main")
        # A commit can start git's housekeeping in the background, which
        # creates and removes .git/objects/maintenance.lock while mktmpdir is
        # deleting the repo, so the cleanup fails with ENOENT.
        git("config", "maintenance.auto", "false")
        git("config", "gc.auto", "0")
        git("config", "user.email", "spec@example.com")
        git("config", "user.name", "Spec")
        yield dir
      end
    end
  end

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def commit_all(message = "change")
    git("add", "--all")
    git("commit", "--quiet", "--allow-empty", "-m", message)
  end

  def numbered(count)
    (1..count).map { |n| "line #{n}\n" }.join
  end

  def lines(*ranges)
    Evilution::LineSet.new(ranges)
  end

  describe "#call" do
    it "returns the lines changed by commits since the ref" do
      in_git_repo do
        write("lib/foo.rb", numbered(10))
        commit_all
        git("checkout", "--quiet", "-b", "feature")
        write("lib/foo.rb", numbered(10).sub("line 3\n", "three\n").sub("line 8\n", "eight\neight and a half\n"))
        commit_all

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(3..3, 8..9))
      end
    end

    it "leaves out what the ref gained after the branch left it" do
      in_git_repo do
        write("lib/foo.rb", numbered(10))
        commit_all
        git("checkout", "--quiet", "-b", "feature")
        write("lib/foo.rb", numbered(10).sub("line 2\n", "two\n"))
        commit_all
        git("checkout", "--quiet", "main")
        write("lib/bar.rb", "bar\n")
        commit_all
        git("checkout", "--quiet", "feature")

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(2..2))
      end
    end

    it "counts the changes not yet committed, staged or not" do
      in_git_repo do
        write("lib/foo.rb", numbered(10))
        write("lib/bar.rb", numbered(5))
        commit_all
        write("lib/foo.rb", numbered(10).sub("line 4\n", "four\n"))
        write("lib/bar.rb", numbered(5).sub("line 5\n", "five\n"))
        git("add", "lib/bar.rb")

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(4..4), "lib/bar.rb" => lines(5..5))
      end
    end

    it "counts every line of a file git does not track yet" do
      in_git_repo do
        write("lib/foo.rb", numbered(3))
        commit_all
        write("lib/new.rb", numbered(4))

        expect(described_class.new("main").call).to eq("lib/new.rb" => lines(1..Float::INFINITY))
      end
    end

    it "leaves out untracked files git ignores" do
      in_git_repo do
        write(".gitignore", "tmp/\n")
        commit_all
        write("tmp/scratch.rb", "x\n")

        expect(described_class.new("main").call).to eq({})
      end
    end

    it "leaves out deleted files" do
      in_git_repo do
        write("lib/foo.rb", numbered(3))
        commit_all
        git("checkout", "--quiet", "-b", "feature")
        FileUtils.rm("lib/foo.rb")
        commit_all

        expect(described_class.new("main").call).to eq({})
      end
    end

    it "counts the lines either side of lines that were only deleted" do
      in_git_repo do
        write("lib/foo.rb", numbered(10))
        commit_all
        write("lib/foo.rb", numbered(10).sub("line 5\nline 6\n", ""))

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(4..5))
      end
    end

    it "counts the first line when the lines deleted were the first ones" do
      in_git_repo do
        write("lib/foo.rb", numbered(5))
        commit_all
        write("lib/foo.rb", numbered(5).sub("line 1\nline 2\n", ""))

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(1..1))
      end
    end

    it "counts only the edited lines of a renamed file, under its new name" do
      in_git_repo do
        write("lib/old.rb", numbered(20))
        commit_all
        git("checkout", "--quiet", "-b", "feature")
        git("mv", "lib/old.rb", "lib/new.rb")
        write("lib/new.rb", numbered(20).sub("line 7\n", "seven\n"))
        commit_all

        expect(described_class.new("main").call).to eq("lib/new.rb" => lines(7..7))
      end
    end

    it "leaves out a file that was only renamed" do
      in_git_repo do
        write("lib/old.rb", numbered(20))
        commit_all
        git("mv", "lib/old.rb", "lib/new.rb")

        expect(described_class.new("main").call).to eq({})
      end
    end

    it "reads added lines that look like a file header as content" do
      in_git_repo do
        write("lib/foo.rb", numbered(3))
        commit_all
        write("lib/foo.rb", "#{numbered(3)}++ b/lib/other.rb\n@@ -1 +1 @@\n")

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(4..5))
      end
    end

    it "reads paths with spaces, quotes and non-ASCII characters as they are" do
      in_git_repo do
        names = ["lib/with space.rb", "lib/with\"quote.rb", "lib/ünïcödé.rb", "lib/tab\there.rb"]
        names.each { |name| write(name, numbered(3)) }
        commit_all
        names.each { |name| write(name, numbered(3).sub("line 2\n", "two\n")) }

        expect(described_class.new("main").call).to eq(names.to_h { |name| [name, lines(2..2)] })
      end
    end

    it "leaves out binary files" do
      in_git_repo do
        write("lib/blob.bin", "\x00\x01\x02".b)
        commit_all
        write("lib/blob.bin", "\x00\x03\x02".b)

        expect(described_class.new("main").call).to eq({})
      end
    end

    it "names files relative to the directory it runs in, leaving out those outside it" do
      in_git_repo do
        write("app/lib/foo.rb", numbered(3))
        write("other/bar.rb", numbered(3))
        commit_all
        write("app/lib/foo.rb", numbered(3).sub("line 1\n", "one\n"))
        write("other/bar.rb", numbered(3).sub("line 1\n", "one\n"))
        write("app/lib/fresh.rb", "x\n")

        Dir.chdir("app") do
          expect(described_class.new("main").call)
            .to eq("lib/foo.rb" => lines(1..1), "lib/fresh.rb" => lines(1..Float::INFINITY))
        end
      end
    end

    it "ignores the user's diff settings" do
      in_git_repo do
        write("lib/foo.rb", numbered(3))
        commit_all
        git("config", "diff.noprefix", "true")
        git("config", "diff.mnemonicPrefix", "true")
        git("config", "color.diff", "always")
        write("lib/foo.rb", numbered(3).sub("line 3\n", "three\n"))

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(3..3))
      end
    end

    it "reads non-ASCII names of untracked files as UTF-8" do
      in_git_repo do
        commit_all
        write("lib/ünï.rb", "x\n")

        expect(described_class.new("main").call).to eq("lib/ünï.rb" => lines(1..Float::INFINITY))
      end
    end

    it "reads changes to a file that is not valid UTF-8" do
      in_git_repo do
        write("lib/latin.rb", "caf\xE9\nb\n".b)
        commit_all
        write("lib/latin.rb", "caf\xE9\nc\n".b)

        expect(described_class.new("main").call).to eq("lib/latin.rb" => lines(2..2))
      end
    end

    it "names the new file of a working-tree diff under a mnemonic prefix setting" do
      in_git_repo do
        write("lib/foo.rb", numbered(3))
        commit_all
        git("config", "diff.mnemonicPrefix", "true")
        write("lib/foo.rb", numbered(3).sub("line 2\n", "two\n"))

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(2..2))
      end
    end

    it "ignores an external diff tool the user configured" do
      in_git_repo do
        write("lib/foo.rb", numbered(3))
        commit_all
        git("config", "diff.external", "true")
        write("lib/foo.rb", numbered(3).sub("line 2\n", "two\n"))

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(2..2))
      end
    end

    it "diffs the files as they are, not as a textconv filter shows them" do
      in_git_repo do
        write(".gitattributes", "*.rb diff=shifted\n")
        write("lib/foo.rb", numbered(3))
        commit_all
        git("config", "diff.shifted.textconv", "sed -e 1iheader")
        write("lib/foo.rb", numbered(3).sub("line 2\n", "two\n"))

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(2..2))
      end
    end

    it "finds renames when the user turned rename detection off" do
      in_git_repo do
        write("lib/old.rb", numbered(20))
        commit_all
        git("config", "diff.renames", "false")
        git("mv", "lib/old.rb", "lib/new.rb")
        write("lib/new.rb", numbered(20).sub("line 7\n", "seven\n"))

        expect(described_class.new("main").call).to eq("lib/new.rb" => lines(7..7))
      end
    end

    it "keeps hunks apart whatever diff.interHunkContext the user set" do
      in_git_repo do
        write("lib/foo.rb", numbered(20))
        commit_all
        write("lib/foo.rb", numbered(20).sub("line 3\n", "three\n").sub("line 7\n", "seven\n").sub("line 12\n", "twelve\n"))
        ENV.update("GIT_CONFIG_COUNT" => "1", "GIT_CONFIG_KEY_0" => "diff.interHunkContext", "GIT_CONFIG_VALUE_0" => "5")

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(3..3, 7..7, 12..12))
      end
    end

    it "takes no context lines from GIT_DIFF_OPTS" do
      in_git_repo do
        write("lib/foo.rb", numbered(20))
        commit_all
        write("lib/foo.rb", numbered(20).sub("line 12\n", "twelve\n"))
        ENV["GIT_DIFF_OPTS"] = "--unified=5"

        expect(described_class.new("main").call).to eq("lib/foo.rb" => lines(12..12))
      end
    end

    it "raises a ConfigError carrying git's message when a git command fails" do
      in_git_repo do
        commit_all
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3)
          .with({ "GIT_DIFF_OPTS" => nil }, "git", "-c", "core.quotePath=false", "diff", any_args)
          .and_return(["", "fatal: boom\n", instance_double(Process::Status, success?: false)])

        expect { described_class.new("main").call }
          .to raise_error(Evilution::ConfigError, "--since: git diff failed: fatal: boom")
      end
    end

    it "raises a ConfigError when git cannot be run" do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "git")

      expect { described_class.new("main").call }
        .to raise_error(Evilution::ConfigError, /--since needs git, which could not be run: .*git/)
    end

    it "does not report an error other than a failed system call as git missing" do
      allow(Open3).to receive(:capture3).and_raise(ArgumentError, "bad option")

      expect { described_class.new("main").call }.to raise_error(ArgumentError, "bad option")
    end

    it "takes a commit as the ref" do
      in_git_repo do
        write("lib/foo.rb", numbered(3))
        commit_all
        sha = `git rev-parse HEAD`.strip
        write("lib/foo.rb", numbered(3).sub("line 1\n", "one\n"))
        commit_all

        expect(described_class.new(sha).call).to eq("lib/foo.rb" => lines(1..1))
      end
    end

    it "raises a ConfigError naming a ref git does not know" do
      in_git_repo do
        commit_all

        expect { described_class.new("nope").call }
          .to raise_error(Evilution::ConfigError, /--since: unknown git ref 'nope'/)
      end
    end

    it "does not read a ref that starts with a dash as an option" do
      in_git_repo do
        commit_all

        expect { described_class.new("--all").call }
          .to raise_error(Evilution::ConfigError, /unknown git ref '--all'/)
      end
    end

    it "raises a ConfigError when the ref shares no history with HEAD, as in a shallow clone" do
      in_git_repo do
        write("lib/foo.rb", "x\n")
        commit_all
        git("checkout", "--quiet", "--orphan", "lonely")
        write("lib/foo.rb", "y\n")
        commit_all("unrelated")

        expect { described_class.new("main").call }
          .to raise_error(Evilution::ConfigError, /no merge base between main and HEAD.*fetch-depth: 0/m)
      end
    end

    it "raises a ConfigError outside a git repository" do
      Dir.mktmpdir("changed_lines_spec") do |dir|
        Dir.chdir(dir) do
          expect { described_class.new("main").call }
            .to raise_error(Evilution::ConfigError, "--since needs a git repository: #{Dir.pwd} is not inside one")
        end
      end
    end
  end
end
