# frozen_string_literal: true

class IndexAccessMultibyte
  def multibyte_before_access(h)
    label = "привет"
    h[:key]
  end
end
