require 'ostruct'
require 'api_helpers/shop_cart_usa_api'

class ShopCartUsaSource < Source
  def initialize
    super(:name => 'ShopCartUSA',
          :homepage => 'http://www.shopcartusa.com/',
          :cpc => 45,
          :offer_enabled => false,
          :offer_ttl_seconds => 900,
          :use_for_merchant_ratings => false,
          :offer_affiliate => false,
          :supports_lifetime_ratings => false,
          :batch_fetch_delay => 1)
  end
  
  def url_for_merchant_source_page(merchant_source_code)
    "http://www.shopcartusa.com/#{merchant_source_code}/"
  end

  def code_from_merchant_source_page_url(merchant_source_page_url)
    merchant_source_page_url
  end

  def fetch_merchant_source(merchant_source_page_url)
    ShopCartUsaAPI.fetch_merchant_source(merchant_source_page_url)
    # ShopCartUSA does not have a merchant page to scrape to given their merchant ID (I know, lame)
#    merchant_source = OpenStruct.new
#    merchant_source.source = self
#    merchant_source.code = merchant_source_page_url
#    merchant_source.name = ''
#    merchant_source
  end

  def format_rating(merchant_source)
    merchant_source.get_merchant_rating
  end

  def nullify_offer_url(offer_url)
    offer_url.gsub(/s=id1/, 's=id0')
  end

  def fetch_offers(product_source_codes)
    unless product_source_codes.empty?
      ShopCartUsaAPI::find_offers_by_product_id(product_source_codes.first)
    else
      []
    end
  end
end
