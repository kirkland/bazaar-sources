require 'api_helpers/amazon_api'

class AmazonSource < Source
  AMAZON_MERCHANT_PERMALINK = 'amazon'

  def initialize
    super(:name => 'Amazon',
          :homepage => 'http://www.amazon.com/',
          :cpc => 25,
          :offer_enabled => true,
          :offer_ttl_seconds => 3600,
          :use_for_merchant_ratings => true,
          :offer_affiliate => true,
          :supports_lifetime_ratings => false,
          :batch_fetch_delay => 2)
  end

  def url_for_merchant_source_page(merchant_source_code)
    AmazonAPI.at_a_glance_url(merchant_source_code)
  end

  def fetch_merchant_source(merchant_source_page_url)
    amazon_merchant_code = merchant_source_page_url
    if merchant_source_page_url.match /(\?|&)seller=(A.+?)(&.*|$)/
      amazon_merchant_code = $2
    end
    delay_fetch
    properties = AmazonAPI.seller_lookup(amazon_merchant_code)
    
    { :source => self,
      :code => properties[:seller_id],
      :name => properties[:merchant_name],
      :merchant_rating => properties[:average_feedback_rating] * 20.0,
      :num_merchant_reviews => properties[:total_feedback],
      :logo_url => properties[:logo_url],
      :homepage => properties[:homepage] }
  end
  
  # fake it.
  def source_product_id(product)
    product.amazon_asins.empty? ? nil : product.amazon_asins.first.source_id
  end

  def fetch_best_offer(product, min_num_offers_to_qualify=nil)
    delay_fetch
    offers = fetch_product_offers(product)
    if !min_num_offers_to_qualify.nil? && offers.length < min_num_offers_to_qualify
      return nil
    end
    offers.inject(nil) do |best_offer, offer|
      unless offer.price.nil? || offer.shipping.nil?
        if best_offer.nil? || (offer.price + offer.shipping) < (best_offer.price + best_offer.shipping)
          best_offer = offer
        end
      end
      best_offer
    end
  end

  def fetch_street_price(product)
    best_offer = fetch_best_offer(product, 3)
    best_offer.nil? ? nil : best_offer.total_price
  end

  def self.nullify_offer_url(offer_url)
    offer_url.gsub(/#{AMAZON_ASSOCIATE_TAG}/, AMAZON_ASSOCIATE_TAG_ALT)
  end

  def nullify_offer_url(offer_url)
    AmazonSource.nullify_offer_url(offer_url)
  end

  def offer_affiliate_for_merchant?(merchant)
    !merchant.nil? && merchant.permalink == AMAZON_MERCHANT_PERMALINK
  end

  def affiliate_wrap_deal_url(deal_url, nullify=false)
    nullify ? nullify_offer_url(deal_url) : deal_url
  end

  def fetch_product_offers(product)
    AmazonAPI::findOffersForProduct(product).values
  end
end
