# frozen_string_literal: true

require_relative "../hooks"

class Evilution::Hooks::Loader
  def self.call(registry, config_hooks = nil)
    return registry if config_hooks.nil?

    unless config_hooks.is_a?(Hash)
      raise Evilution::ConfigError, "hooks must be a mapping of event names to file paths, got #{config_hooks.class}"
    end
    return registry if config_hooks.empty?

    config_hooks.each do |event, paths|
      event = event.to_sym
      Array(paths).each do |path|
        handler = load_hook_file(path)
        registry.register(event) { |payload| handler.call(payload) }
      end
    end

    registry
  end

  def self.load_hook_file(path)
    raise Evilution::ConfigError, "hook file not found: #{path}" unless File.exist?(path)

    result = Module.new.module_eval(File.read(path), path, 1)
    raise Evilution::ConfigError, "hook file #{path} must return a Proc, got #{result.class}" unless result.is_a?(Proc)

    result
  end

  private_class_method :load_hook_file
end
