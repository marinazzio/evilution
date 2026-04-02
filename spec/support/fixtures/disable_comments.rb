# frozen_string_literal: true

class DisableCommentsFixture
  def normal_method
    1 + 2
  end

  # evilution:disable
  def disabled_method
    "should be skipped"
  end

  def method_with_inline_disable
    x = 1 # evilution:disable
    y = 2
    x + y
  end

  # evilution:disable
  def another_disabled
    "also skipped"
  end
  # evilution:enable

  def method_in_range
    # evilution:disable
    a = dangerous_call
    b = another_call
    # evilution:enable
    a + b
  end

  def unclosed_range
    # evilution:disable
    forever_disabled
  end
end
