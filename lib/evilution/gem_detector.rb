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

    def gem_entry_for(root)
      gem_name = gem_name_for(root)
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

    def gem_name_for(root)
      specs = Dir.glob(File.join(root, "*.gemspec"))
      return nil if specs.empty?

      File.basename(specs.first, ".gemspec")
    end
  end
end
