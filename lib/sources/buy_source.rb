class BuySource < Source
  BUY_MERCHANT_PERMALINK = 'buy-com'
  BUY_AFFILIATE_PID = '3332520'
  BUY_AFFILIATE_URL_PREFIX = "http://affiliate.buy.com/gateway.aspx?adid=17662&pid=#{BUY_AFFILIATE_PID}&aid=10391416&sURL="

  def initialize
    super(:name => 'Buy.com',
          :keyname => 'BUY',
          :homepage => 'http://www.buy.com/',
          :cpc => 7,
          :offer_enabled => false,
          :offer_ttl_seconds => 86400,
          :use_for_merchant_ratings => false,
          :offer_affiliate => true,
          :batch_fetch_delay => 2)
  end
  
  def nullify_offer_url(offer_url)
    offer_url.gsub(/#{BUY_AFFILIATE_PID}/, '')
  end

  def offer_affiliate_for_merchant?(merchant)
    !merchant.nil? && merchant.permalink == BUY_MERCHANT_PERMALINK
  end

  def affiliate_wrap_deal_url(deal_url, nullify=false)
    offer_url = BUY_AFFILIATE_URL_PREFIX
    offer_url += CGI::escape(deal_url)
    nullify ? nullify_offer_url(offer_url) : offer_url
  end
end
