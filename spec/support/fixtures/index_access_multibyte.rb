# frozen_string_literal: true

class IndexAccessMultibyte
  def multibyte_before_access(h, k)
    label = "привет"
    h[k]
  end
end
