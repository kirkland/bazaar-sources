require 'api_helpers/reseller_ratings_api'

class ResellerRatingsSource < Source
  def initialize
    super(:name => 'ResellerRatings.com',
          :homepage => 'http://www.resellerratings.com/',
          :cpc => 0,
          :offer_enabled => false,
          :offer_ttl_seconds => 0,
          :use_for_merchant_ratings => true,
          :offer_affiliate => false,
          :supports_lifetime_ratings => true,
          :batch_fetch_delay => 5,
          :product_code_regexp => /^\d{9}$/,
          :product_code_examples => ['652196596', '676109333'],
          :product_page_link_erb => "http://resellerratings.nextag.com/<%= product_code %>/resellerratings/prices-html")
  end
  
  def url_for_merchant_source_page(merchant_source_code)
    "http://www.resellerratings.com/seller#{merchant_source_code}.html"
  end

  def url_for_merchant_source_page_alt(merchant_source_alt_code)
    "http://www.resellerratings.com/store/#{merchant_source_alt_code}"
  end

  def code_from_merchant_source_page_url(merchant_source_page_url)
    nil
  end

  def fetch_merchant_source(merchant_source_page_url)
    delay_fetch
    ResellerRatingsAPI.fetch_merchant_source(merchant_source_page_url)
  end

  def search_for_merchant_source(search_text)
    ResellerRatingsAPI.search_for_merchant_source(search_text)
  end

  def search_for_merchant_source_best_match(search_text)
    ResellerRatingsAPI.search_for_merchant_source_best_match(search_text)
  end

  def format_rating(merchant_source)
    '%01.1f/10' % (merchant_source.get_merchant_rating.to_f / 10.0)
  end
end
