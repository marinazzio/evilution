# frozen_string_literal: true

module Fm
  STORE = {} # rubocop:disable Style/MutableConstant -- the shared state under test

  class Writer
    def with_entry(key, value)
      STORE[key] = value
      yield
    ensure
      STORE.delete(key)
    end
  end

  class Reader
    def read(key)
      return :none if key.nil?

      STORE.fetch(key, :missing)
    end
  end

  class Router
    def route(n)
      n > 0 ? :positive : Helper.new.label(n) # rubocop:disable Style/NumericPredicate -- the mutated comparison
    end
  end

  class Helper
    def label(n)
      n.positive? ? :positive : :other
    end
  end

  class Looper
    def count(n)
      i = 0
      i += 1 while i < n
      i
    end
  end
end
