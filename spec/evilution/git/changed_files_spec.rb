# frozen_string_literal: true

require "evilution/git/changed_files"
require "tmpdir"

RSpec.describe Evilution::Git::ChangedFiles do
  subject(:detector) { described_class.new }

  def in_git_repo(&block)
    Dir.mktmpdir("changed_files_spec") do |dir|
      Dir.chdir(dir) do
        system("git", "init", "--quiet", "--initial-branch=main", out: File::NULL, err: File::NULL)
        system("git", "config", "user.email", "spec@example.com")
        system("git", "config", "user.name", "Spec")
        block.call(dir)
      end
    end
  end

  def commit(file, content, message)
    require "fileutils"
    FileUtils.mkdir_p(File.dirname(file)) if File.dirname(file) != "."
    File.write(file, content)
    system("git", "add", file, out: File::NULL, err: File::NULL)
    system("git", "commit", "--quiet", "-m", message, out: File::NULL, err: File::NULL)
  end

  describe "#call" do
    context "when changed Ruby files exist" do
      it "returns .rb files under lib/" do
        allow(detector).to receive(:detect_main_branch).and_return("main")
        allow(detector).to receive(:run_git).with("merge-base", "HEAD", "main").and_return("abc123")
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123..HEAD").and_return(
          "lib/foo.rb\nlib/bar.rb\nREADME.md\n"
        )

        expect(detector.call).to eq(["lib/foo.rb", "lib/bar.rb"])
      end

      it "returns .rb files under app/" do
        allow(detector).to receive(:detect_main_branch).and_return("main")
        allow(detector).to receive(:run_git).with("merge-base", "HEAD", "main").and_return("abc123")
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123..HEAD").and_return(
          "app/models/user.rb\napp/views/index.html.erb\n"
        )

        expect(detector.call).to eq(["app/models/user.rb"])
      end

      it "raises when only non-.rb files changed" do
        allow(detector).to receive(:detect_main_branch).and_return("main")
        allow(detector).to receive(:run_git).with("merge-base", "HEAD", "main").and_return("abc123")
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123..HEAD").and_return(
          "lib/foo.yml\nspec/foo_spec.rb\nGemfile\n"
        )

        expect { detector.call }.to raise_error(Evilution::Error, /no changed Ruby files/)
      end

      it "raises when changed files are outside lib/ and app/" do
        allow(detector).to receive(:detect_main_branch).and_return("main")
        allow(detector).to receive(:run_git).with("merge-base", "HEAD", "main").and_return("abc123")
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123..HEAD").and_return(
          "spec/foo_spec.rb\nbin/console\nsrc/thing.rb\n"
        )

        expect { detector.call }.to raise_error(Evilution::Error, /no changed Ruby files/)
      end
    end

    context "main branch detection" do
      it "detects master when main does not exist" do
        allow(detector).to receive(:detect_main_branch).and_return("master")
        allow(detector).to receive(:run_git).with("merge-base", "HEAD", "master").and_return("abc123")
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123..HEAD").and_return(
          "lib/foo.rb\n"
        )

        expect(detector.call).to eq(["lib/foo.rb"])
      end
    end

    context "error conditions" do
      it "raises when not in a git repository" do
        allow(detector).to receive(:detect_main_branch).and_raise(
          Evilution::Error, "not a git repository"
        )

        expect { detector.call }.to raise_error(Evilution::Error, /not a git repository/)
      end

      it "raises when no main branch is found" do
        allow(detector).to receive(:detect_main_branch).and_raise(
          Evilution::Error, "could not detect main branch (tried main, master)"
        )

        expect { detector.call }.to raise_error(Evilution::Error, /could not detect main branch/)
      end

      it "raises when no changes are detected" do
        allow(detector).to receive(:detect_main_branch).and_return("main")
        allow(detector).to receive(:run_git).with("merge-base", "HEAD", "main").and_return("abc123")
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123..HEAD").and_return("")

        expect { detector.call }.to raise_error(Evilution::Error, /no changed Ruby files/)
      end
    end
  end

  describe "#detect_main_branch" do
    it "returns main when it exists" do
      allow(detector).to receive(:branch_exists?).with("main").and_return(true)

      expect(detector.send(:detect_main_branch)).to eq("main")
    end

    it "returns master when main does not exist" do
      allow(detector).to receive(:branch_exists?).with("main").and_return(false)
      allow(detector).to receive(:branch_exists?).with("master").and_return(true)

      expect(detector.send(:detect_main_branch)).to eq("master")
    end

    it "falls back to origin/main when local branches do not exist" do
      allow(detector).to receive(:branch_exists?).with("main").and_return(false)
      allow(detector).to receive(:branch_exists?).with("master").and_return(false)
      allow(detector).to receive(:branch_exists?).with("origin/main").and_return(true)

      expect(detector.send(:detect_main_branch)).to eq("origin/main")
    end

    it "falls back to origin/master when no other branches exist" do
      allow(detector).to receive(:branch_exists?).with("main").and_return(false)
      allow(detector).to receive(:branch_exists?).with("master").and_return(false)
      allow(detector).to receive(:branch_exists?).with("origin/main").and_return(false)
      allow(detector).to receive(:branch_exists?).with("origin/master").and_return(true)

      expect(detector.send(:detect_main_branch)).to eq("origin/master")
    end

    it "raises when no branch candidates exist" do
      allow(detector).to receive(:branch_exists?).with("main").and_return(false)
      allow(detector).to receive(:branch_exists?).with("master").and_return(false)
      allow(detector).to receive(:branch_exists?).with("origin/main").and_return(false)
      allow(detector).to receive(:branch_exists?).with("origin/master").and_return(false)

      expect { detector.send(:detect_main_branch) }.to raise_error(
        Evilution::Error, /could not detect main branch/
      )
    end

    it "re-raises not a git repository error from branch_exists?" do
      allow(detector).to receive(:run_git).with("rev-parse", "--verify", "main").and_raise(
        Evilution::Error, "not a git repository"
      )

      expect { detector.send(:detect_main_branch) }.to raise_error(
        Evilution::Error, /not a git repository/
      )
    end
  end

  # Integration-level coverage (EV-auk5 / GH #1297). The mocked-out specs above
  # never exercise run_git / branch_exists? / detect_main_branch internals.
  # These specs run real git commands inside a tmp repo so mutations on the
  # backtick command, string interpolation, separators, rescue logic, and
  # success-status checks get exercised.
  describe "#run_git (real git)" do
    it "returns trimmed stdout on success" do
      in_git_repo do
        commit("a.rb", "# a", "init")

        result = detector.send(:run_git, "rev-parse", "--verify", "HEAD")

        expect(result).to be_a(String)
        expect(result).not_to be_empty
        expect(result).not_to end_with("\n")
        expect(result).not_to start_with(" ")
      end
    end

    it "joins arguments with a single space" do
      in_git_repo do
        commit("a.rb", "# a", "init")

        # rev-parse with two args must join with " " — joining with "" makes "rev-parseHEAD"
        expect { detector.send(:run_git, "rev-parse", "HEAD") }.not_to raise_error
      end
    end

    it "raises 'not a git repository' Evilution::Error outside any git repo" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect do
            detector.send(:run_git, "rev-parse", "--verify", "HEAD")
          end.to raise_error(Evilution::Error, /not a git repository/)
        end
      end
    end

    it "raises generic 'git command failed' Evilution::Error when a non-repo error fires" do
      in_git_repo do
        commit("a.rb", "# a", "init")

        expect do
          detector.send(:run_git, "rev-parse", "--verify", "nonexistent-ref-xyz")
        end.to raise_error(Evilution::Error, /git command failed/)
      end
    end

    it "includes the command and stderr in the failure message" do
      in_git_repo do
        commit("a.rb", "# a", "init")

        expect do
          detector.send(:run_git, "rev-parse", "--verify", "nonexistent-ref-xyz")
        end.to raise_error(Evilution::Error, /rev-parse.*nonexistent-ref-xyz/m)
      end
    end

    # Asserts space-separated command echo in failure message. Without space
    # join, the message reads 'rev-parse--verifynonexistent-ref-xyz' which is
    # unreadable but currently survives unless we check exact spacing.
    it "joins command parts with single spaces in the failure echo" do
      in_git_repo do
        commit("a.rb", "# a", "init")

        expect do
          detector.send(:run_git, "rev-parse", "--verify", "nonexistent-ref-xyz")
        end.to raise_error(Evilution::Error, /rev-parse --verify nonexistent-ref-xyz/)
      end
    end

    # Asserts the literal ': ' separator between the echoed command and the
    # captured stderr in the failure message. Without it, mutations that
    # interpolate the empty string survive.
    it "separates the command echo and stderr with ': '" do
      in_git_repo do
        commit("a.rb", "# a", "init")

        expect do
          detector.send(:run_git, "rev-parse", "--verify", "nonexistent-ref-xyz")
        end.to raise_error(Evilution::Error, /nonexistent-ref-xyz: /)
      end
    end

    # Assert the captured stderr is interpolated (not dropped to nil/empty).
    # `git rev-parse --verify <bad>` prints "fatal: Needed a single revision".
    it "interpolates the captured stderr output into the failure message" do
      in_git_repo do
        commit("a.rb", "# a", "init")

        expect do
          detector.send(:run_git, "rev-parse", "--verify", "nonexistent-ref-xyz")
        end.to raise_error(Evilution::Error, /fatal: Needed a single revision/)
      end
    end

    it "does NOT raise generic 'git command failed' for the not-a-git-repo case" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect do
            detector.send(:run_git, "rev-parse", "--verify", "HEAD")
          end.to raise_error(Evilution::Error) { |e| expect(e.message).not_to include("git command failed") }
        end
      end
    end
  end

  describe "#branch_exists? (real git)" do
    it "returns true for an existing branch" do
      in_git_repo do
        commit("a.rb", "# a", "init")

        expect(detector.send(:branch_exists?, "main")).to eq(true)
      end
    end

    it "returns false for an absent branch (not literal/truthy other)" do
      in_git_repo do
        commit("a.rb", "# a", "init")

        result = detector.send(:branch_exists?, "ghost-branch")
        expect(result).to eq(false)
        expect(result).not_to eq(nil)
        expect(result).not_to eq(true)
      end
    end

    it "re-raises the 'not a git repository' Evilution::Error without swallowing" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect do
            detector.send(:branch_exists?, "main")
          end.to raise_error(Evilution::Error, /not a git repository/)
        end
      end
    end

    # Asserts the literal "--verify" flag is sent. Without it, `git rev-parse`
    # accepts ambiguous refs (e.g. tag/path) and returns false data, so a
    # mutation that replaces "--verify" with "" can silently survive.
    it "passes --verify to git rev-parse" do
      in_git_repo do
        commit("a.rb", "# a", "init")
        # Create a path named after a non-branch ref so plain `rev-parse <name>`
        # would not error, but `rev-parse --verify <name>` does.
        FileUtils.mkdir_p("not-a-ref")

        # `git rev-parse not-a-ref` resolves the path; --verify rejects it as a
        # non-rev name.
        expect(detector.send(:branch_exists?, "not-a-ref")).to eq(false)
      end
    end
  end

  describe "#detect_main_branch (real git)" do
    it "returns 'main' when present" do
      in_git_repo do
        commit("a.rb", "# a", "init")

        expect(detector.send(:detect_main_branch)).to eq("main")
      end
    end

    it "returns 'master' when only master exists" do
      in_git_repo do
        commit("a.rb", "# a", "init")
        system("git", "branch", "-m", "main", "master", out: File::NULL, err: File::NULL)

        expect(detector.send(:detect_main_branch)).to eq("master")
      end
    end

    it "lists all four candidate branch names in error when none exist" do
      in_git_repo do
        commit("a.rb", "# a", "init")
        system("git", "branch", "-m", "main", "develop", out: File::NULL, err: File::NULL)

        expect { detector.send(:detect_main_branch) }.to raise_error(Evilution::Error) do |e|
          expect(e.message).to include("main")
          expect(e.message).to include("master")
          expect(e.message).to include("origin/main")
          expect(e.message).to include("origin/master")
        end
      end
    end

    it "separates candidate branch names with ', ' in the error message" do
      in_git_repo do
        commit("a.rb", "# a", "init")
        system("git", "branch", "-m", "main", "develop", out: File::NULL, err: File::NULL)

        expect { detector.send(:detect_main_branch) }.to raise_error(Evilution::Error, %r{main, master, origin/main, origin/master})
      end
    end

    it "closes the candidate-list parenthesis in the error message" do
      in_git_repo do
        commit("a.rb", "# a", "init")
        system("git", "branch", "-m", "main", "develop", out: File::NULL, err: File::NULL)

        expect { detector.send(:detect_main_branch) }.to raise_error(Evilution::Error, %r{origin/master\)\z})
      end
    end
  end

  describe "#call (real git)" do
    it "returns lib/ .rb files changed since main" do
      in_git_repo do
        commit("lib/a.rb", "# a", "init lib")
        system("git", "checkout", "-b", "feature", "--quiet", out: File::NULL, err: File::NULL)
        commit("lib/b.rb", "# b", "add b")
        commit("lib/c.rb", "# c", "add c")

        expect(detector.call).to match_array(["lib/b.rb", "lib/c.rb"])
      end
    end

    it "splits diff output on newlines (not other separators)" do
      in_git_repo do
        commit("lib/a.rb", "# a", "init")
        system("git", "checkout", "-b", "feature", "--quiet", out: File::NULL, err: File::NULL)
        commit("lib/b.rb", "# b", "add b")
        commit("lib/c.rb", "# c", "add c")

        # Each entry is a distinct file. If split used "" or " ", we'd get one
        # giant string instead of two paths.
        result = detector.call
        expect(result.length).to eq(2)
        expect(result).to all(match(%r{\Alib/[a-z]\.rb\z}))
      end
    end

    it "excludes non-Ruby files" do
      in_git_repo do
        commit("lib/a.rb", "# a", "init")
        system("git", "checkout", "-b", "feature", "--quiet", out: File::NULL, err: File::NULL)
        commit("lib/b.rb", "# b", "add b")
        commit("README.md", "readme", "add readme")

        expect(detector.call).to eq(["lib/b.rb"])
      end
    end

    it "excludes spec/ Ruby files" do
      in_git_repo do
        commit("lib/a.rb", "# a", "init")
        system("git", "checkout", "-b", "feature", "--quiet", out: File::NULL, err: File::NULL)
        commit("lib/b.rb", "# b", "add b")
        commit("spec/a_spec.rb", "# spec", "add spec")

        expect(detector.call).to eq(["lib/b.rb"])
      end
    end

    it "includes app/ Ruby files" do
      in_git_repo do
        commit("lib/a.rb", "# a", "init")
        system("git", "checkout", "-b", "feature", "--quiet", out: File::NULL, err: File::NULL)
        commit("app/m/user.rb", "# u", "add user")

        expect(detector.call).to eq(["app/m/user.rb"])
      end
    end

    it "raises with detected main branch name interpolated in the error" do
      in_git_repo do
        commit("lib/a.rb", "# a", "init")
        # No subsequent commits → no diff → no .rb files

        expect { detector.call }.to raise_error(Evilution::Error, /no changed Ruby files.*main/m)
      end
    end
  end

  describe "#ruby_source_file? (boundary cases)" do
    it "accepts lib/foo.rb" do
      expect(detector.send(:ruby_source_file?, "lib/foo.rb")).to be(true)
    end

    it "accepts app/models/user.rb" do
      expect(detector.send(:ruby_source_file?, "app/models/user.rb")).to be(true)
    end

    it "rejects spec/foo_spec.rb" do
      expect(detector.send(:ruby_source_file?, "spec/foo_spec.rb")).to be(false)
    end

    it "rejects lib/foo.yml" do
      expect(detector.send(:ruby_source_file?, "lib/foo.yml")).to be(false)
    end

    it "rejects bare foo.rb (no prefix)" do
      expect(detector.send(:ruby_source_file?, "foo.rb")).to be(false)
    end

    it "rejects empty path" do
      expect(detector.send(:ruby_source_file?, "")).to be(false)
    end
  end
end
