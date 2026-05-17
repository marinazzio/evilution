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

    it "returns nil for a nil path without raising" do
      expect { described_class.gem_root_for(nil) }.not_to raise_error
      expect(described_class.gem_root_for(nil)).to be_nil
    end

    it "returns nil when the path's parent directory does not exist" do
      # A gemspec sits at @tmp, but the path's immediate parent dir is
      # missing: starting_dir must reject it (not climb to the gemspec).
      write_gemspec(@tmp, "ancestor")
      missing = File.join(@tmp, "no_such_dir", "deeper", "file.rb")
      expect { described_class.gem_root_for(missing) }.not_to raise_error
      expect(described_class.gem_root_for(missing)).to be_nil
    end

    it "returns the cached value on a repeated lookup for the same directory" do
      write_gemspec(@tmp, "cached")
      lib_file = write_gem_entry(@tmp, "cached")
      expect(described_class.gem_root_for(lib_file)).to eq(@tmp)
      # Second call must hit the cache and return the same root (a non-nil
      # value), not the cache hash itself and not nil.
      expect(described_class.gem_root_for(lib_file)).to eq(@tmp)
    end

    it "serves a stale cache entry on a cache hit rather than recomputing" do
      write_gemspec(@tmp, "stale")
      lib_file = write_gem_entry(@tmp, "stale")
      dir = File.expand_path(File.dirname(lib_file))
      # Prime the cache, then poison the entry. A genuine cache hit returns
      # the poisoned value; recomputation would return the real root.
      described_class.gem_root_for(lib_file)
      cache = described_class.instance_variable_get(:@cache)
      cache[dir] = "/poisoned/root"
      expect(described_class.gem_root_for(lib_file)).to eq("/poisoned/root")
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

    it "detects the gem root when given a directory path directly" do
      write_gemspec(@tmp, "dirinput")
      sub = File.join(@tmp, "lib", "dirinput")
      FileUtils.mkdir_p(sub)
      expect(described_class.gem_root_for(sub)).to eq(@tmp)
    end

    it "detects the gem root when given the gem root directory itself" do
      write_gemspec(@tmp, "rootinput")
      expect(described_class.gem_root_for(@tmp)).to eq(@tmp)
    end

    it "uses the parent directory when the path itself is a missing file in an existing dir" do
      write_gemspec(@tmp, "missingfile")
      FileUtils.mkdir_p(File.join(@tmp, "lib"))
      # lib/ exists, but ghost.rb does not — starting_dir falls back to lib/.
      ghost = File.join(@tmp, "lib", "ghost.rb")
      expect(described_class.gem_root_for(ghost)).to eq(@tmp)
    end
  end

  describe ".reset_cache!" do
    it "clears cached lookups so a poisoned entry is no longer served" do
      write_gemspec(@tmp, "resettable")
      lib_file = write_gem_entry(@tmp, "resettable")
      dir = File.expand_path(File.dirname(lib_file))
      described_class.gem_root_for(lib_file)
      cache = described_class.instance_variable_get(:@cache)
      cache[dir] = "/poisoned/root"

      described_class.reset_cache!

      expect(cache).to be_empty
      # After clearing, a fresh lookup recomputes the real root.
      expect(described_class.gem_root_for(lib_file)).to eq(@tmp)
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

    it "returns lib/<name>.rb (flat) for a hyphenated name when only the flat file exists" do
      write_gemspec(@tmp, "dry-monads")
      FileUtils.mkdir_p(File.join(@tmp, "lib"))
      flat = File.join(@tmp, "lib", "dry-monads.rb")
      File.write(flat, "module DryMonads; end\n")
      # No lib/dry/monads.rb — the dotted branch misses, the flat branch hits.
      expect(described_class.gem_entry_for(@tmp)).to eq(flat)
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

      it "picks the subdir-matched gemspec even when it is not the shortest name" do
        # Shortest name is "aa"; the subdir match must override the
        # min-by-length fallback.
        write_gemspec(@tmp, "aa")
        write_gemspec(@tmp, "bb-extra")
        write_gem_entry(@tmp, "aa")
        bb_flat = File.join(@tmp, "lib", "bb-extra.rb")
        File.write(bb_flat, "module BbExtra; end\n")
        FileUtils.mkdir_p(File.join(@tmp, "lib", "bb-extra"))
        target = File.join(@tmp, "lib", "bb-extra", "thing.rb")
        File.write(target, "")

        entry = described_class.gem_entry_for(@tmp, target_paths: [target])
        expect(entry).to eq(bb_flat)
      end

      it "skips a nil entry in target_paths without raising" do
        write_gemspec(@tmp, "dotenv")
        write_gemspec(@tmp, "dotenv-rails")
        write_gem_entry(@tmp, "dotenv")
        rails_entry = write_gem_entry(@tmp, "dotenv-rails")

        entry = nil
        expect do
          entry = described_class.gem_entry_for(@tmp, target_paths: [nil, rails_entry])
        end.not_to raise_error
        expect(entry).to eq(rails_entry)
      end

      it "ignores target paths outside the gem's lib directory for subdir matching" do
        # The target lives outside <root>/lib, so lib_subdir_for returns nil
        # and the subdir matcher must not match it; fallback to shortest name.
        write_gemspec(@tmp, "dotenv")
        write_gemspec(@tmp, "dotenv-rails")
        write_gem_entry(@tmp, "dotenv")
        write_gem_entry(@tmp, "dotenv-rails")
        outside = File.join(@tmp, "spec", "dotenv-rails", "x.rb")
        FileUtils.mkdir_p(File.dirname(outside))
        File.write(outside, "")

        entry = described_class.gem_entry_for(@tmp, target_paths: [outside])
        expect(entry).to eq(File.join(@tmp, "lib", "dotenv.rb"))
      end

      it "lib_subdir_for returns nil for a path that is not under <root>/lib" do
        # Direct check of the start_with?("#{lib_root}/") guard: a sibling
        # directory that merely shares the "lib" prefix must be rejected.
        outside = File.join(@tmp, "libexec", "dotenv", "x.rb")
        expect(described_class.send(:lib_subdir_for, @tmp, outside)).to be_nil
      end

      it "lib_subdir_for returns the first lib segment for a path under <root>/lib" do
        # Exercises the slice offset: the result must be the directory name
        # ("dotenv"), with no stray leading slash from an off-by-one.
        under = File.join(@tmp, "lib", "dotenv", "parser.rb")
        expect(described_class.send(:lib_subdir_for, @tmp, under)).to eq("dotenv")
      end

      it "matches the subdir using the leading path segment, not the file basename" do
        # Target nested two levels under lib/<subdir>/ — only the first
        # segment ("dotenv") should be used to match the gemspec.
        write_gemspec(@tmp, "dotenv")
        write_gemspec(@tmp, "dotenv-rails")
        write_gem_entry(@tmp, "dotenv")
        write_gem_entry(@tmp, "dotenv-rails")
        nested = File.join(@tmp, "lib", "dotenv", "deep", "nested.rb")
        FileUtils.mkdir_p(File.dirname(nested))
        File.write(nested, "")

        entry = described_class.gem_entry_for(@tmp, target_paths: [nested])
        expect(entry).to eq(File.join(@tmp, "lib", "dotenv.rb"))
      end
    end
  end
end
