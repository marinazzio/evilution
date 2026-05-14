# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "evilution/gem_detector"

RSpec.describe Evilution::GemDetector do
  around do |example|
    Dir.mktmpdir("evilution-gem-detector") do |tmp|
      @tmp = tmp
      described_class.reset_cache!
      example.run
    end
  end

  def write_gemspec(root, name)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "#{name}.gemspec"), <<~RUBY)
      Gem::Specification.new do |s|
        s.name = #{name.inspect}
        s.version = "0.0.0"
      end
    RUBY
  end

  def write_gem_entry(root, gem_name)
    rel = "lib/#{gem_name.tr("-", "/")}.rb"
    abs = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, "module GemDetectorTest; end\n")
    abs
  end

  describe ".gem_root_for" do
    it "returns the gem root when path lives under one with a gemspec" do
      write_gemspec(@tmp, "myproj")
      lib_file = write_gem_entry(@tmp, "myproj")
      expect(described_class.gem_root_for(lib_file)).to eq(@tmp)
    end

    it "returns nil when no gemspec exists up the tree" do
      File.write(File.join(@tmp, "thing.rb"), "")
      expect(described_class.gem_root_for(File.join(@tmp, "thing.rb"))).to be_nil
    end

    it "returns nil for a non-existent path" do
      expect(described_class.gem_root_for(File.join(@tmp, "nope.rb"))).to be_nil
    end

    it "walks up from a deeply nested file to find the gemspec" do
      write_gemspec(@tmp, "deep")
      nested = File.join(@tmp, "lib", "deep", "inner", "code.rb")
      FileUtils.mkdir_p(File.dirname(nested))
      File.write(nested, "")
      expect(described_class.gem_root_for(nested)).to eq(@tmp)
    end

    it "stops at the filesystem root without error" do
      FileUtils.mkdir_p(File.join(@tmp, "a", "b"))
      File.write(File.join(@tmp, "a", "b", "x.rb"), "")
      expect(described_class.gem_root_for(File.join(@tmp, "a", "b", "x.rb"))).to be_nil
    end
  end

  describe ".gem_root_for_any" do
    it "returns the first detected root among a list of paths" do
      write_gemspec(@tmp, "anyproj")
      lib_file = write_gem_entry(@tmp, "anyproj")
      paths = [File.join(@tmp, "nowhere.rb"), lib_file]
      expect(described_class.gem_root_for_any(paths)).to eq(@tmp)
    end

    it "returns nil when no path is under a gem root" do
      File.write(File.join(@tmp, "thing.rb"), "")
      expect(described_class.gem_root_for_any([File.join(@tmp, "thing.rb")])).to be_nil
    end

    it "returns nil for an empty list" do
      expect(described_class.gem_root_for_any([])).to be_nil
    end
  end

  describe ".gem_entry_for" do
    it "returns lib/<name>.rb when name is single-token and the file exists" do
      write_gemspec(@tmp, "single")
      entry = write_gem_entry(@tmp, "single")
      expect(described_class.gem_entry_for(@tmp)).to eq(entry)
    end

    it "returns lib/<a>/<b>.rb for a hyphenated gem name (Bundler convention)" do
      write_gemspec(@tmp, "dry-monads")
      entry = write_gem_entry(@tmp, "dry-monads") # writes lib/dry/monads.rb
      expect(described_class.gem_entry_for(@tmp)).to eq(entry)
    end

    it "prefers lib/<dotted-path>.rb over lib/<name>.rb when both exist" do
      write_gemspec(@tmp, "dry-monads")
      dotted = write_gem_entry(@tmp, "dry-monads")
      flat = File.join(@tmp, "lib", "dry-monads.rb")
      File.write(flat, "require \"dry/monads\"\n")
      expect(described_class.gem_entry_for(@tmp)).to eq(dotted)
    end

    it "returns nil when no matching lib/<name>.rb exists" do
      write_gemspec(@tmp, "noentry")
      expect(described_class.gem_entry_for(@tmp)).to be_nil
    end

    it "returns nil when no gemspec exists in the root" do
      FileUtils.mkdir_p(File.join(@tmp, "lib"))
      File.write(File.join(@tmp, "lib", "thing.rb"), "")
      expect(described_class.gem_entry_for(@tmp)).to be_nil
    end

    describe "multi-gemspec disambiguation (EV-b0ee / #1206)" do
      # bkeepers/dotenv is the motivating case: dotenv.gemspec and
      # dotenv-rails.gemspec sit side-by-side. With no signal, the old
      # `Dir.glob.first` pick was filesystem-order-dependent and often
      # selected dotenv-rails.gemspec, which preloaded lib/dotenv/rails.rb
      # and exploded on `uninitialized constant Rails`.

      it "picks the gemspec matching the target file's first lib subdir" do
        write_gemspec(@tmp, "dotenv")
        write_gemspec(@tmp, "dotenv-rails")
        write_gem_entry(@tmp, "dotenv") # lib/dotenv.rb
        FileUtils.mkdir_p(File.join(@tmp, "lib", "dotenv"))
        File.write(File.join(@tmp, "lib", "dotenv", "parser.rb"), "")
        write_gem_entry(@tmp, "dotenv-rails") # lib/dotenv/rails.rb

        entry = described_class.gem_entry_for(
          @tmp, target_paths: [File.join(@tmp, "lib", "dotenv", "parser.rb")]
        )
        expect(entry).to eq(File.join(@tmp, "lib", "dotenv.rb"))
      end

      it "picks the gemspec matching the target when target is the rails companion" do
        write_gemspec(@tmp, "dotenv")
        write_gemspec(@tmp, "dotenv-rails")
        write_gem_entry(@tmp, "dotenv")
        rails_entry = write_gem_entry(@tmp, "dotenv-rails") # lib/dotenv/rails.rb

        entry = described_class.gem_entry_for(
          @tmp, target_paths: [rails_entry]
        )
        expect(entry).to eq(rails_entry)
      end

      it "falls back to the shortest gemspec name when no target_paths match a gemspec" do
        write_gemspec(@tmp, "dotenv")
        write_gemspec(@tmp, "dotenv-rails")
        write_gem_entry(@tmp, "dotenv")
        write_gem_entry(@tmp, "dotenv-rails")

        # Target file under a directory that matches neither gemspec name.
        FileUtils.mkdir_p(File.join(@tmp, "lib", "other"))
        File.write(File.join(@tmp, "lib", "other", "x.rb"), "")
        entry = described_class.gem_entry_for(
          @tmp, target_paths: [File.join(@tmp, "lib", "other", "x.rb")]
        )
        expect(entry).to eq(File.join(@tmp, "lib", "dotenv.rb"))
      end

      it "falls back to the shortest gemspec name when target_paths is nil" do
        write_gemspec(@tmp, "dotenv")
        write_gemspec(@tmp, "dotenv-rails")
        write_gem_entry(@tmp, "dotenv")
        write_gem_entry(@tmp, "dotenv-rails")

        expect(described_class.gem_entry_for(@tmp)).to eq(
          File.join(@tmp, "lib", "dotenv.rb")
        )
      end

      it "leaves single-gemspec behavior unchanged regardless of target_paths" do
        write_gemspec(@tmp, "solo")
        entry = write_gem_entry(@tmp, "solo")

        expect(described_class.gem_entry_for(@tmp, target_paths: [entry])).to eq(entry)
        expect(described_class.gem_entry_for(@tmp)).to eq(entry)
      end
    end
  end
end
