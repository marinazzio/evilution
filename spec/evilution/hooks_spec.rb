# frozen_string_literal: true

RSpec.describe Evilution::Hooks do
  let(:hooks) { described_class.new }

  describe "#register" do
    it "registers a hook for a known event" do
      handler = ->(_payload) {}
      hooks.register(:worker_process_start, &handler)

      expect(hooks.handlers_for(:worker_process_start)).to include(handler)
    end

    it "raises for an unknown event" do
      expect { hooks.register(:bogus) { nil } }
        .to raise_error(ArgumentError, /unknown hook event.*bogus/i)
    end

    it "supports multiple handlers for the same event" do
      calls = []
      hooks.register(:worker_process_start) { calls << :first }
      hooks.register(:worker_process_start) { calls << :second }

      hooks.fire(:worker_process_start)

      expect(calls).to eq(%i[first second])
    end

    it "returns self for chaining" do
      result = hooks.register(:worker_process_start) { nil }

      expect(result).to eq(hooks)
    end
  end

  describe "#fire" do
    it "calls all handlers for the event in registration order" do
      calls = []
      hooks.register(:mutation_insert_pre) { |payload| calls << [:pre, payload] }
      hooks.register(:mutation_insert_pre) { |payload| calls << [:pre2, payload] }

      hooks.fire(:mutation_insert_pre, mutation: "test")

      expect(calls).to eq([[:pre, { mutation: "test" }], [:pre2, { mutation: "test" }]])
    end

    it "does nothing when no handlers are registered" do
      expect { hooks.fire(:worker_process_start) }.not_to raise_error
    end

    it "raises for an unknown event" do
      expect { hooks.fire(:bogus) }
        .to raise_error(ArgumentError, /unknown hook event.*bogus/i)
    end

    it "passes keyword arguments as a payload hash" do
      received = nil
      hooks.register(:mutation_insert_post) { |payload| received = payload }

      hooks.fire(:mutation_insert_post, mutation: "m1", file_path: "/tmp/test.rb")

      expect(received).to eq({ mutation: "m1", file_path: "/tmp/test.rb" })
    end

    it "passes empty hash when no payload given" do
      received = nil
      hooks.register(:worker_process_start) { |payload| received = payload }

      hooks.fire(:worker_process_start)

      expect(received).to eq({})
    end
  end

  describe "#clear" do
    it "removes all handlers for a specific event" do
      hooks.register(:worker_process_start) { nil }
      hooks.clear(:worker_process_start)

      expect(hooks.handlers_for(:worker_process_start)).to be_empty
    end

    it "removes all handlers when no event given" do
      hooks.register(:worker_process_start) { nil }
      hooks.register(:mutation_insert_pre) { nil }
      hooks.clear

      expect(hooks.handlers_for(:worker_process_start)).to be_empty
      expect(hooks.handlers_for(:mutation_insert_pre)).to be_empty
    end

    it "raises for an unknown event" do
      expect { hooks.clear(:bogus) }
        .to raise_error(ArgumentError, /unknown hook event.*bogus/i)
    end
  end

  describe "#handlers_for" do
    it "returns a copy of the handlers array" do
      hooks.register(:worker_process_start) { nil }

      handlers = hooks.handlers_for(:worker_process_start)
      handlers.clear

      expect(hooks.handlers_for(:worker_process_start).length).to eq(1)
    end

    it "raises for an unknown event" do
      expect { hooks.handlers_for(:bogus) }
        .to raise_error(ArgumentError, /unknown hook event.*bogus/i)
    end
  end

  describe "supported events" do
    it "supports all documented hook events" do
      expected_events = %i[
        worker_process_start
        mutation_insert_pre
        mutation_insert_post
        setup_integration_pre
        setup_integration_post
      ]

      expected_events.each do |event|
        expect { hooks.register(event) { nil } }.not_to raise_error
      end
    end
  end

  describe "error handling" do
    it "propagates handler errors by default" do
      hooks.register(:worker_process_start) { raise "boom" }

      expect { hooks.fire(:worker_process_start) }.to raise_error(RuntimeError, "boom")
    end
  end

  describe ".from_config" do
    it "returns an empty hooks instance when config has no hooks" do
      config_hooks = {}
      result = described_class.from_config(config_hooks)

      expect(result).to be_a(described_class)
      expect(result.handlers_for(:worker_process_start)).to be_empty
    end

    it "registers callables from a config hash" do
      called = false
      config_hooks = {
        worker_process_start: [->(_payload) { called = true }]
      }
      result = described_class.from_config(config_hooks)
      result.fire(:worker_process_start)

      expect(called).to be true
    end

    it "raises for unknown events in config" do
      config_hooks = { bogus: [->(_payload) {}] }

      expect { described_class.from_config(config_hooks) }
        .to raise_error(ArgumentError, /unknown hook event.*bogus/i)
    end
  end
end
