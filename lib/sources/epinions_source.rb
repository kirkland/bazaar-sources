require 'ostruct'

class EpinionsSource < Source
  def initialize
    super(:name => 'Epinions',
          :homepage => 'http://www.epinions.com/',
          :cpc => 0,
          :offer_enabled => false,
          :offer_ttl_seconds => 0,
          :use_for_merchant_ratings => true,
          :offer_affiliate => false,
          :supports_lifetime_ratings => false,
          :batch_fetch_delay => 1)
  end

  def url_for_merchant_source_page(merchant_source_code)
    "http://www.epinions.com/#{merchant_source_code}"
  end

  def code_from_merchant_source_page_url(merchant_source_page_url)
    merchant_source_page_url.match(/epinions\.com\/([^\/\?#]*)/)[1]
  end

  def fetch_merchant_source(merchant_source_page_url)
    merchant_source_page_url.gsub!(/\/display_~.*$/, '')
    delay_fetch
    doc = Hpricot(open(merchant_source_page_url))

    merchant_source = OpenStruct.new
    merchant_source.source = self

    # merchant name
    element = doc.at('h1[@class = "title"]')
    unless element.nil?
      name = element.inner_text.strip
      merchant_source.name = name
    end

    # merchant logo
    element = doc.at('img[@name = "product_image"]')
    unless element.nil?
      logo_url = element.attributes['src']
      logo_url.gsub!(/-resized\d+/, '')
      merchant_source.logo_url = logo_url
    end

    # merchant code
    merchant_source.code = code_from_merchant_source_page_url(merchant_source_page_url)

    # merchant rating
    element = doc.at('span[text() *= "Overall store rating:"]/../img')
    element = doc.at('span[text() *= "Overall service rating:"]/../img') if element.nil?
    unless element.nil?
      merchant_rating = element.attributes['alt'].match(/Store Rating: ((\d|,)*\.?\d)/)[1]
      merchant_source.merchant_rating = merchant_rating.to_f * 20.0 unless merchant_rating.nil?
    end

    # Num Merchant Reviews
    element = doc.at('span[@class = "sgr"]')
    unless element.nil?
      num_merchant_reviews = element.inner_text.match(/Reviewed by (\d+) customer/)[1]
      merchant_source.num_merchant_reviews = num_merchant_reviews.delete(',').to_i unless num_merchant_reviews.nil? || num_merchant_reviews.empty?
    end

    # Homepage
    element = doc.at('span[text() = "Web Site"]../../td[2]/span/a')
    unless element.nil?
      homepage = element.inner_text.strip.downcase
      merchant_source.homepage = homepage
    end

    merchant_source
  end

  def format_rating(merchant_source)
    '%01.1f/5.0' % (merchant_source.get_merchant_rating.to_f / 20.0)
  end
end
