# frozen_string_literal: true

require "evilution/git/changed_files"

RSpec.describe Evilution::Git::ChangedFiles do
  subject(:detector) { described_class.new }

  describe "#call" do
    context "when changed Ruby files exist" do
      it "returns .rb files under lib/" do
        allow(detector).to receive(:detect_main_branch).and_return("main")
        allow(detector).to receive(:run_git).with("merge-base", "HEAD", "main").and_return("abc123")
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123").and_return(
          "lib/foo.rb\nlib/bar.rb\nREADME.md\n"
        )

        expect(detector.call).to eq(["lib/foo.rb", "lib/bar.rb"])
      end

      it "returns .rb files under app/" do
        allow(detector).to receive(:detect_main_branch).and_return("main")
        allow(detector).to receive(:run_git).with("merge-base", "HEAD", "main").and_return("abc123")
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123").and_return(
          "app/models/user.rb\napp/views/index.html.erb\n"
        )

        expect(detector.call).to eq(["app/models/user.rb"])
      end

      it "raises when only non-.rb files changed" do
        allow(detector).to receive(:detect_main_branch).and_return("main")
        allow(detector).to receive(:run_git).with("merge-base", "HEAD", "main").and_return("abc123")
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123").and_return(
          "lib/foo.yml\nspec/foo_spec.rb\nGemfile\n"
        )

        expect { detector.call }.to raise_error(Evilution::Error, /no changed Ruby files/)
      end

      it "raises when changed files are outside lib/ and app/" do
        allow(detector).to receive(:detect_main_branch).and_return("main")
        allow(detector).to receive(:run_git).with("merge-base", "HEAD", "main").and_return("abc123")
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123").and_return(
          "spec/foo_spec.rb\nbin/console\nsrc/thing.rb\n"
        )

        expect { detector.call }.to raise_error(Evilution::Error, /no changed Ruby files/)
      end
    end

    context "main branch detection" do
      it "detects master when main does not exist" do
        allow(detector).to receive(:detect_main_branch).and_return("master")
        allow(detector).to receive(:run_git).with("merge-base", "HEAD", "master").and_return("abc123")
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123").and_return(
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
        allow(detector).to receive(:run_git).with("diff", "--name-only", "--diff-filter=ACMR", "abc123").and_return("")

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

    it "raises when neither main nor master exists" do
      allow(detector).to receive(:branch_exists?).with("main").and_return(false)
      allow(detector).to receive(:branch_exists?).with("master").and_return(false)

      expect { detector.send(:detect_main_branch) }.to raise_error(
        Evilution::Error, /could not detect main branch/
      )
    end
  end
end
