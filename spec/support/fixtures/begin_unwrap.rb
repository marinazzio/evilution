# frozen_string_literal: true

class BeginUnwrapExample
  def simple_begin
    begin # rubocop:disable Style/RedundantBegin
      do_work
    end
  end

  def multiline_begin
    begin # rubocop:disable Style/RedundantBegin
      setup
      process
      cleanup
    end
  end

  def begin_with_rescue
    begin # rubocop:disable Style/RedundantBegin
      do_work
    rescue StandardError
      fallback
    end
  end

  def begin_with_ensure
    begin # rubocop:disable Style/RedundantBegin
      do_work
    ensure
      cleanup
    end
  end

  def no_begin
    do_work
  end
end
