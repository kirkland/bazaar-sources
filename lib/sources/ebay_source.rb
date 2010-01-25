class EbaySource < Source
  EBAY_MERCHANT_PERMALINK = 'ebay'
  EBAY_AFFILIATE_PID = '711-53200-19255-0'
  EBAY_DEFAULT_CAMPAIGN_ID = '5336205246'
  EBAY_ADMIN_CAMPAIGN_ID = '5336210401'
  EBAY_AFFILIATE_URL_PREFIX = "http://rover.ebay.com/rover/1/#{EBAY_AFFILIATE_PID}/1?type=4&campid=#{EBAY_DEFAULT_CAMPAIGN_ID}&toolid=10001&customid=&mpre="

  def initialize
    super(:name => 'eBay.com',
          :homepage => 'http://www.ebay.com/',
          :cpc => 10,
          :offer_enabled => false,
          :offer_ttl_seconds => 86400,
          :use_for_merchant_ratings => false,
          :offer_affiliate => true,
          :supports_lifetime_ratings => false,
          :batch_fetch_delay => 2,
          :product_code_regexp => nil,
          :product_code_examples => [])
  end
  
  def nullify_offer_url(offer_url)
    offer_url.gsub(/#{EBAY_DEFAULT_CAMPAIGN_ID}/, EBAY_ADMIN_CAMPAIGN_ID)
  end

  def offer_affiliate_for_merchant?(merchant)
    !merchant.nil? && merchant.permalink == EBAY_MERCHANT_PERMALINK
  end

  def affiliate_wrap_deal_url(deal_url, nullify=false)
    offer_url = EBAY_AFFILIATE_URL_PREFIX
    offer_url += CGI::escape(deal_url)
    nullify ? nullify_offer_url(offer_url) : offer_url
  end
end
