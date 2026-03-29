# frozen_string_literal: true

class Evilution::Hooks
  EVENTS = %i[
    worker_process_start
    mutation_insert_pre
    mutation_insert_post
    setup_integration_pre
    setup_integration_post
  ].freeze

  def initialize
    @handlers = EVENTS.to_h { |event| [event, []] }
  end

  def register(event, &block)
    validate_event!(event)
    raise ArgumentError, "a block must be provided when registering handler for #{event}" unless block

    @handlers[event] << block
    self
  end

  def fire(event, **payload)
    validate_event!(event)
    @handlers[event].each { |handler| handler.call(payload) }
  end

  def clear(event = nil)
    if event
      validate_event!(event)
      @handlers[event].clear
    else
      @handlers.each_value(&:clear)
    end
  end

  def handlers_for(event)
    validate_event!(event)
    @handlers[event].dup
  end

  def self.from_config(config_hooks)
    hooks = new
    return hooks if config_hooks.nil? || config_hooks.empty?

    config_hooks.each do |event, callables|
      Array(callables).each { |callable| hooks.register(event) { |payload| callable.call(payload) } }
    end
    hooks
  end

  private

  def validate_event!(event)
    raise ArgumentError, "unknown hook event: #{event}" unless EVENTS.include?(event)
  end
end
