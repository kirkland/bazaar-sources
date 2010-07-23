require 'api_helpers/amazon'

class AmazonSource < Source
  AMAZON_MERCHANT_PERMALINK = 'amazon'

  def initialize
    super(:name => 'Amazon',
          :homepage => 'http://www.amazon.com/',
          :cpc => 12,
          :offer_enabled => true,
          :offer_ttl_seconds => 3600,
          :use_for_merchant_ratings => true,
          :offer_affiliate => true,
          :supports_lifetime_ratings => false,
          :batch_fetch_delay => 2,
          :product_code_regexp => /^[a-zA-Z0-9]{10}$/,
          :product_code_examples => ['B000HEC7BO', 'B002YP45EQ'],
          :product_page_link_erb => "http://www.amazon.com/gp/product/<%= product_code %>")
  end

  def api
    @api ||= Amazon::ProductAdvertising.new
  end

  def url_for_merchant_source_page(merchant_source_code)
    api.at_a_glance_url(merchant_source_code)
  end

  def fetch_merchant_source(merchant_source_page_url)
    amazon_merchant_code = merchant_source_page_url
    if merchant_source_page_url.match /(\?|&)seller=(A.+?)(&.*|$)/
      amazon_merchant_code = $2
    end
    delay_fetch
    properties = api.seller_lookup(amazon_merchant_code)
    
    { :source => self,
      :code => properties[:seller_id],
      :name => properties[:merchant_name],
      :merchant_rating => properties[:average_feedback_rating] * 20.0,
      :num_merchant_reviews => properties[:total_feedback],
      :logo_url => properties[:logo_url],
      :homepage => properties[:homepage] }
  end
  
  def fetch_best_offer(product_code, min_num_offers_to_qualify=nil)
    delay_fetch
    offers = fetch_offers(product_code)
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

  def fetch_street_price(product_code)
    best_offer = fetch_best_offer(product_code, 3)
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

  def fetch_offers(product_code)
    begin
      api.find_offers_by_asin(product_code).values
    rescue Amazon::AsinNotFoundError => ex
      raise Source::ProductNotFoundError.new(ex.message << " w/ #{product_code}", keyname, product_code)
    rescue Amazon::AsinFatalError => ex
      raise Source::ProductFatalError.new(ex.message << " w/ #{product_code}", keyname, product_code)
    rescue => ex
      raise Source::GeneralError.new(ex.message << " w/ #{product_code}", keyname)
    end
  end
end
