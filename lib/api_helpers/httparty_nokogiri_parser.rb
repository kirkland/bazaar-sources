require 'nokogiri'

class HttpartyNokogiriParser < HTTParty::Parser

  protected

  def xml
    Nokogiri::XML(body)
  end

  def html
    Nokogiri::HTML(body)
  end
end
