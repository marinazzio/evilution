# frozen_string_literal: true

require_relative "../hooks"

class Evilution::Hooks::Loader
  def self.call(registry, config_hooks = nil)
    return registry if config_hooks.nil? || config_hooks.empty?

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

    result = eval(File.read(path), TOPLEVEL_BINDING, path, 1) # rubocop:disable Security/Eval
    raise Evilution::ConfigError, "hook file #{path} must return a Proc, got #{result.class}" unless result.is_a?(Proc)

    result
  end

  private_class_method :load_hook_file
end
