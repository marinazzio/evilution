# frozen_string_literal: true

class ReceiverSimplification
  Point = Data.define(:value) do
    def label = value.to_s
  end

  def call(seat_str:) = Seat.find_by(number: seat_str.to_i)

  def present(params)
    params[:x].presence
  end

  def interpolated(value)
    "seat #{value.to_s}"
  end

  def safe(value)
    value&.to_i
  end

  def keyword_default(seat: raw_seat.to_i)
    seat
  end

  def block_body(list)
    list.map { |str| str.to_i }
  end

  def hash_value(value)
    { number: value.to_i }
  end
end
