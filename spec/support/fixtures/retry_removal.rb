# frozen_string_literal: true

class RetryRemovalExample
  def simple_retry
    attempts = 0
    begin
      do_work
    rescue StandardError
      attempts += 1
      retry if attempts < 3
    end
  end

  def unconditional_retry
    begin # rubocop:disable Style/RedundantBegin
      connect
    rescue ConnectionError
      retry
    end
  end

  def retry_in_method_rescue
    do_work
  rescue StandardError
    retry
  end

  def no_retry
    begin # rubocop:disable Style/RedundantBegin
      do_work
    rescue StandardError
      fallback
    end
  end
end
