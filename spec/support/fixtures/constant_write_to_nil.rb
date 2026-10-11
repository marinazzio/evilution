class ConstantWriteToNilTarget
  LIMIT = 10
  NAME = "target".freeze
  DEFAULTS = {
    size: 1,
    mode: :fast
  }.freeze
  HANDLER = ->(value) { value + 1 }
  COMPUTED = compute(LIMIT)
  UNSET = nil
  QUERY = <<~SQL
    SELECT 1
  SQL
  Builder = Class.new do
    INNER = 5

    def build = INNER
  end
  Point = Struct.new(:x, :y)

  def limit
    LIMIT
  end
end

ConstantWriteToNilTarget::EXTRA = [1, 2]
