# frozen_string_literal: true

module Evilution::GemDetector
  @cache = {}
  @mutex = Mutex.new

  class << self
    def gem_root_for(path)
      return nil if path.nil?

      dir = starting_dir(path)
      return nil if dir.nil?

      @mutex.synchronize do
        return @cache[dir] if @cache.key?(dir)

        @cache[dir] = walk_up(dir)
      end
    end

    def gem_root_for_any(paths)
      Array(paths).each do |path|
        root = gem_root_for(path)
        return root if root
      end
      nil
    end

    def gem_entry_for(root, target_paths: nil)
      gem_name = gem_name_for(root, target_paths: target_paths)
      return nil unless gem_name

      dotted = File.join(root, "lib", "#{gem_name.tr("-", "/")}.rb")
      return dotted if File.file?(dotted)

      flat = File.join(root, "lib", "#{gem_name}.rb")
      return flat if File.file?(flat)

      nil
    end

    def reset_cache!
      @mutex.synchronize { @cache.clear }
    end

    private

    def starting_dir(path)
      return File.expand_path(path) if File.directory?(path)
      return File.expand_path(File.dirname(path)) if File.file?(path)

      parent = File.expand_path(File.dirname(path))
      File.directory?(parent) ? parent : nil
    end

    def walk_up(dir)
      current = dir
      loop do
        return current unless Dir.glob(File.join(current, "*.gemspec")).empty?

        parent = File.dirname(current)
        return nil if parent == current

        current = parent
      end
    end

    # When the root has multiple gemspecs (e.g. dotenv ships dotenv.gemspec
    # alongside dotenv-rails.gemspec), `Dir.glob.first` is filesystem-order-
    # dependent and often picks the wrong one — preloading the rails companion
    # then raises `uninitialized constant Rails`. Disambiguate by:
    #   1. exact-entry match — if a target is *exactly* the lib entry for a
    #      gemspec (`lib/dotenv/rails.rb` for `dotenv-rails.gemspec`), use it
    #   2. first-lib-subdir match — `lib/dotenv/parser.rb` matches `dotenv`
    #   3. fall back to the shortest gemspec basename — `dotenv` <
    #      `dotenv-rails`, which is the conventional "parent" gem.
    def gem_name_for(root, target_paths: nil)
      names = Dir.glob(File.join(root, "*.gemspec")).map { |p| File.basename(p, ".gemspec") }
      return nil if names.empty?
      return names.first if names.length == 1

      paths = Array(target_paths)
      match_by_exact_entry(root, names, paths) ||
        match_by_subdir(root, names, paths) ||
        names.min_by(&:length)
    end

    def match_by_exact_entry(root, names, paths)
      paths.each do |path|
        next if path.nil?

        expanded = File.expand_path(path)
        match = names.find { |n| entry_paths_for(root, n).include?(expanded) }
        return match if match
      end
      nil
    end

    def entry_paths_for(root, gem_name)
      [
        File.join(root, "lib", "#{gem_name.tr("-", "/")}.rb"),
        File.join(root, "lib", "#{gem_name}.rb")
      ]
    end

    def match_by_subdir(root, names, paths)
      paths.each do |path|
        subdir = lib_subdir_for(root, path)
        next if subdir.nil?

        match = names.find { |n| n == subdir }
        return match if match
      end
      nil
    end

    # For `<root>/lib/dotenv/parser.rb` returns "dotenv". For
    # `<root>/lib/dotenv-rails.rb` returns "dotenv-rails". Returns nil when
    # the target isn't under `<root>/lib/`.
    def lib_subdir_for(root, path)
      return nil if path.nil?

      expanded = File.expand_path(path)
      lib_root = File.join(File.expand_path(root), "lib")
      return nil unless expanded.start_with?("#{lib_root}/")

      relative = expanded[(lib_root.length + 1)..]
      first_segment = relative.split("/", 2).first
      File.basename(first_segment, ".rb")
    end
  end
end
