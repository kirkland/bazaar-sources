require 'api_helpers/shop_cart_usa_api'

class ShopCartUsaSource < Source
  def initialize
    super(:name => 'ShopCartUSA',
          :keyname => 'SHOP_CART_USA',
          :homepage => 'http://www.shopcartusa.com/',
          :cpc => 45,
          :offer_enabled => true,
          :offer_ttl_seconds => 900,
          :use_for_merchant_ratings => false,
          :offer_affiliate => false,
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
#    merchant_source = MerchantSource.new
#    merchant_source.source = self
#    merchant_source.code = merchant_source_page_url
#    merchant_source.name = ''
#    merchant_source
  end

  def format_rating(merchant_source)
    merchant_source.get_merchant_rating
  end

  def source_product_id(product)
    product.shopping_product_id.blank? ? nil : product.shopping_product_id
  end

  def nullify_offer_url(offer_url)
    offer_url.gsub(/s=id1/, 's=id0')
  end

  def fetch_product_offers(product)
    source_product_id = source_product_id(product)
    unless source_product_id.nil?
      ShopCartUsaAPI::find_offers_by_product_id(source_product_id)
    else
      []
    end
  end
end
