# The corpus program: a ledger that caches its own total.
class Ledger
  attr_reader :rows, :tags

  def initialize(seed = [])
    @rows = []
    @tags = {}
    @total = nil
    seed.each_with_index { |v, i| push("seed#{i}", v) }
  end

  def push(tag, value)
    raise TypeError, "not numeric: #{value}" unless value.is_a?(Numeric)

    @tags[tag] = @rows.length
    @rows << value
    @total = nil
    self
  end

  def total
    @total ||= @rows.select { |r| r > 0 }.sum
  end

  def merge(other)
    other.tags.each { |tag, at| push(tag, other.rows[at]) }
    self
  end
end

led = Ledger.new([1, 2, 3])
led.push("late", 4)
puts "total=#{led.total}"
