# frozen_string_literal: true

require_relative "../hooks"

class Evilution::Hooks::Registry
  def initialize(on_error: nil)
    @handlers = Evilution::Hooks::EVENTS.to_h { |event| [event, []] }
    @on_error = on_error
  end

  def register(event, &block)
    validate_event!(event)
    raise ArgumentError, "a block must be provided when registering handler for #{event}" unless block

    @handlers[event] << block
    self
  end

  def fire(event, **payload)
    validate_event!(event)
    errors = []

    @handlers[event].each do |handler|
      handler.call(payload)
    rescue StandardError => e
      errors << e
      report_error(event, e)
    end

    errors
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

  private

  def validate_event!(event)
    raise ArgumentError, "unknown hook event: #{event}" unless Evilution::Hooks::EVENTS.include?(event)
  end

  def report_error(event, error)
    if @on_error
      @on_error.call(event, error)
    else
      warn "[evilution] hook error in #{event}: #{error.message}"
    end
  end
end
