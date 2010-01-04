module ApiHelper
  def to_i_or_nil(string_value)
    string_value.nil? ? nil : string_value.strip.to_i rescue nil
  end

  def to_d_or_nil(string_value)
    string_value.nil? ? nil : BigDecimal(string_value.strip) rescue nil
  end
end
