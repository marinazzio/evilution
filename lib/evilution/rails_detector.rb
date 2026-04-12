# frozen_string_literal: true

module Evilution::RailsDetector
  MARKER = File.join("config", "application.rb").freeze

  @cache = {}
  @mutex = Mutex.new

  class << self
    def rails_root_for(path)
      return nil if path.nil?

      dir = starting_dir(path)
      return nil if dir.nil?

      @mutex.synchronize do
        return @cache[dir] if @cache.key?(dir)

        @cache[dir] = walk_up(dir)
      end
    end

    def rails_root_for_any(paths)
      Array(paths).each do |path|
        root = rails_root_for(path)
        return root if root
      end
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
        return current if File.file?(File.join(current, MARKER))

        parent = File.dirname(current)
        return nil if parent == current

        current = parent
      end
    end
  end
end
