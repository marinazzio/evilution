# frozen_string_literal: true

RSpec.describe Evilution::Hooks::Registry do
  let(:registry) { described_class.new }

  describe "#register" do
    it "registers a handler for a known event" do
      handler = ->(_payload) {}
      registry.register(:worker_process_start, &handler)

      expect(registry.handlers_for(:worker_process_start)).to include(handler)
    end

    it "raises for an unknown event" do
      expect { registry.register(:bogus) { nil } }
        .to raise_error(ArgumentError, /unknown hook event.*bogus/i)
    end

    it "raises when called without a block" do
      expect { registry.register(:worker_process_start) }
        .to raise_error(ArgumentError, /block must be provided/)
    end

    it "supports multiple handlers for the same event" do
      calls = []
      registry.register(:worker_process_start) { calls << :first }
      registry.register(:worker_process_start) { calls << :second }

      registry.fire(:worker_process_start)

      expect(calls).to eq(%i[first second])
    end

    it "returns self for chaining" do
      result = registry.register(:worker_process_start) { nil }

      expect(result).to eq(registry)
    end
  end

  describe "#fire" do
    it "calls all handlers in registration order" do
      calls = []
      registry.register(:mutation_insert_pre) { |payload| calls << [:a, payload] }
      registry.register(:mutation_insert_pre) { |payload| calls << [:b, payload] }

      registry.fire(:mutation_insert_pre, mutation: "test")

      expect(calls).to eq([[:a, { mutation: "test" }], [:b, { mutation: "test" }]])
    end

    it "does nothing when no handlers are registered" do
      expect { registry.fire(:worker_process_start) }.not_to raise_error
    end

    it "raises for an unknown event" do
      expect { registry.fire(:bogus) }
        .to raise_error(ArgumentError, /unknown hook event.*bogus/i)
    end

    it "passes empty hash when no payload given" do
      received = nil
      registry.register(:worker_process_start) { |payload| received = payload }

      registry.fire(:worker_process_start)

      expect(received).to eq({})
    end

    context "with error isolation" do
      it "catches handler errors and continues to next handler" do
        calls = []
        registry.register(:worker_process_start) { raise "boom" }
        registry.register(:worker_process_start) { calls << :second }

        registry.fire(:worker_process_start)

        expect(calls).to eq([:second])
      end

      it "reports errors to the on_error callback" do
        errors = []
        registry = described_class.new(on_error: ->(event, error) { errors << [event, error.message] })
        registry.register(:mutation_insert_pre) { raise "hook failed" }

        registry.fire(:mutation_insert_pre)

        expect(errors).to eq([[:mutation_insert_pre, "hook failed"]])
      end

      it "warns to stderr when no on_error callback is set" do
        registry.register(:worker_process_start) { raise "boom" }

        expect { registry.fire(:worker_process_start) }
          .to output(/hook error.*worker_process_start.*boom/i).to_stderr
      end

      it "collects all errors and returns them" do
        registry.register(:worker_process_start) { raise "first" }
        registry.register(:worker_process_start) { raise "second" }

        errors = registry.fire(:worker_process_start)

        expect(errors.length).to eq(2)
        expect(errors.map(&:message)).to eq(%w[first second])
      end

      it "returns empty array when no errors occur" do
        registry.register(:worker_process_start) { nil }

        errors = registry.fire(:worker_process_start)

        expect(errors).to be_empty
      end
    end
  end

  describe "#clear" do
    it "removes all handlers for a specific event" do
      registry.register(:worker_process_start) { nil }
      registry.clear(:worker_process_start)

      expect(registry.handlers_for(:worker_process_start)).to be_empty
    end

    it "removes all handlers when no event given" do
      registry.register(:worker_process_start) { nil }
      registry.register(:mutation_insert_pre) { nil }
      registry.clear

      expect(registry.handlers_for(:worker_process_start)).to be_empty
      expect(registry.handlers_for(:mutation_insert_pre)).to be_empty
    end

    it "raises for an unknown event" do
      expect { registry.clear(:bogus) }
        .to raise_error(ArgumentError, /unknown hook event.*bogus/i)
    end
  end

  describe "#handlers_for" do
    it "returns a copy of the handlers array" do
      registry.register(:worker_process_start) { nil }

      handlers = registry.handlers_for(:worker_process_start)
      handlers.clear

      expect(registry.handlers_for(:worker_process_start).length).to eq(1)
    end

    it "raises for an unknown event" do
      expect { registry.handlers_for(:bogus) }
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
        expect { registry.register(event) { nil } }.not_to raise_error
      end
    end
  end
end
