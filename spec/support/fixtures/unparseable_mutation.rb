# frozen_string_literal: true

class UnparseableMutation
  def try_compute(x)
    result = begin; x.to_i; rescue; nil; end
    result
  end
end
