class Operator
  def self.symbol(str)
    case str
    when '+'
      :must
    when '-'
      :must_not
    when nil
      :should
    else
      raise "Unknown operator: #{str}"
    end
  end
end
