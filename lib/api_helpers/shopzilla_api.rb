require 'hpricot'
require 'open-uri'
require 'timeout'

class ShopzillaAPI
  @@default_api_call_timeout = 25
  def self.default_api_call_timeout=(obj)
    @@default_api_call_timeout = obj
  end
  attr_accessor :api_call_timeout

  def initialize
    @logger = Logger.new(STDERR)
  end

  # Find all offers for a product given the (shopzilla) product_id
  def find_offers_by_product_id(product_id)
    result = make_offer_service_request(product_id)
    offers = {}
    unless result.nil?
      merchant_offers = result / 'Products/Product/Offers/Offer'
      merchant_offers.each do |offer|
        merchant_id = offer.attributes['merchantId']
        merchant_name = safe_inner_text(offer.at('merchantName'))
        merchant_rating_elem = offer.at('MerchantRating')
        merchant_rating = normalize_merchant_rating(merchant_rating_elem.attributes['value'].to_f) unless merchant_rating_elem.nil?
        price = get_price_from_node(offer.at('price'))
        shipping = get_price_from_node(offer.at('shipAmount'))
        url = safe_inner_text(offer.at('url'))
        condition = safe_inner_text(offer.at('condition'))
        stock = safe_inner_text(offer.at('stock'))
        if is_likely_new_condition?(condition) && is_likely_in_stock?(stock)
          offers[merchant_id] = ProductOffer.new({ :merchant_code => merchant_id,
                                                   :merchant_name => safe_unescape_html(merchant_name),
                                                   :merchant_logo_url => "http://img.bizrate.com/merchant/#{merchant_id}.gif",
                                                   :cpc => nil,
                                                   :price => price,
                                                   :shipping => shipping,
                                                   :offer_url => safe_unescape_html(url),
                                                   :offer_tier => ProductOffer::OFFER_TIER_ONE,
                                                   :merchant_rating => merchant_rating,
                                                   :num_merchant_reviews => nil })
        end
      end
    end
    offers.values
  end

  def normalize_merchant_rating(merchant_rating)
    merchant_rating.nil? ? nil : (merchant_rating * 10.0).round
  end

  # This method makes a separate API call to get merchant detail info.  It returns a hash that is aligned with 
  # the merchant_source model
  def merchant_source_detail(merchant_id)
    result = make_merchant_service_request(merchant_id)
    return nil if result.nil?
    merchant_element = result / ("Merchants/Merchant[@id=#{merchant_id}]")
    merchant_source = {}
    merchant_source[:source] = 'shopzilla'
    merchant_source[:code] = merchant_id.to_s
    merchant_source[:name] = safe_inner_text(merchant_element.at('name'))
    logo_url = logo_url(merchant_id)
    if verify_logo_url(logo_url)
      merchant_source[:logo_url] = logo_url
    end

    # rating will not exist if unrated (although "unrated" will -- doh!)
    rated = false
    begin
      rating_elem = merchant_element.at('/Rating/Overall')
      unless rating_elem.nil?
        rated = true
        merchant_source[:merchant_rating] = normalize_merchant_rating(rating_elem.attributes['value'].to_f)
      end
    rescue
      merchant_source[:merchant_rating] = 0
    end
    # There are about 38 ways this could fail, so rescue any baddies
    begin
      # URL provided is an entity escaped url to shopzilla/bizrate for example
      # http://www.bizrate.com/rd?t=http%3A%2F%2Fwww.pcnation.com%2Fasp%2Findex.asp%3Faffid%3D308&amp;mid=31427&amp;cat_id=&amp;prod_id=350513557&amp;oid=&amp;pos=1&amp;b_id=18&amp;rf=af1&amp;af_id=3973&amp;af_creative_id=6&amp;af_assettype_id=10&amp;af_placement_id=1
      # http://www.bizrate.com/rd?t=http%3A%2F%2Fad.doubleclick.net%2Fclk%3B23623113%3B12119329%3Bs%3Fhttp%3A%2F%2Fwww.staples.com%2Fwebapp%2Fwcs%2Fstores%2Fservlet%2Fhome%3FstoreId%3D10001%26langId%3D-1%26cm_mmc%3Donline_bizrate-_-search-_-staples_brand-_-staples.com&mid=370&cat_id=&prod_id=&oid=&pos=1&b_id=18&rf=af1&af_id=3973&af_creative_id=6&af_assettype_id=10&af_placement_id=1
      # http://www.bizrate.com/rd?t=http%3A%2F%2Fwww.tigerdirect.com%2Findex.asp%3FSRCCODE%3DBIZRATE&mid=23939&cat_id=&prod_id=&oid=&pos=1&b_id=18&rf=af1&af_id=3973&af_creative_id=6&af_assettype_id=10&af_placement_id=1
      # http://www.bizrate.com/rd?t=http%3A%2F%2Fad.doubleclick.net%2Fclk%3BNEW_1%3B6928611%3Ba%3Fhttp%3A%2F%2Fwww.officedepot.com&mid=814&cat_id=&prod_id=&oid=&pos=1&b_id=18&rf=af1&af_id=3973&af_creative_id=6&af_assettype_id=10&af_placement_id=1
      redir_url = CGI::unescape(merchant_element.at('url').inner_text)
      # the query string will contain a value at the "t" parameter
      t_param_value = redir_url.match(/(\?|&)t=(.+)/)[2]
      if t_param_value.index('doubleclick').nil?
        homepage = t_param_value.match(/https?:\/\/(.+?)(\/|&|\?|$)/)[1]
      else
        homepage = t_param_value.match(/.+https?:\/\/(.+?)(\/|&|\?|$)/)[1]
      end
      merchant_source[:homepage] = "http://#{homepage}/"
    rescue
      merchant_source[:homepage] = nil
    end
    # now, we just need the number of reviews
    if rated
      num_merchant_reviews = safe_inner_text(merchant_element.at('Details/surveyCount'))
      num_merchant_reviews = num_merchant_reviews.blank? ? 0 : num_merchant_reviews.to_i
      merchant_source[:num_merchant_reviews] = num_merchant_reviews
    end
    merchant_source
  end

  def logo_url(merchant_id)
    "http://img.bizrate.com/merchant/#{merchant_id}.gif"
  end

  def verified_logo_url(merchant_id)
    logo_url = logo_url(merchant_id)
    verify_logo_url(logo_url) ? logo_url : nil
  end
  
  # -----------------------------------------------------------------------------------------------
  private
  # -----------------------------------------------------------------------------------------------

  def make_offer_service_request(product_id)
    params = {'productId' => product_id.to_s.strip,
     'offersOnly' => 'true',
     'biddedOnly' => 'true',
     'resultsOffers' => '100',
     'zipCode' => '64141'}
    make_api_request('product', params)
  end

  def make_product_service_request(product_id)
    params = {'productId' => product_id.to_s.strip}
    make_api_request('product', params)
  end

  def make_merchant_service_request(merchant_id)
    params = {'merchantId' => merchant_id.to_s.strip,
              'expandDetails' => 'true'}
    make_api_request('merchant', params)
  end
  
  def make_brand_service_request(category_id, keyword)
    params = {'categoryId' => category_id,
              'keyword' => keyword.strip}
    make_api_request('brands', params)
  end

  def make_taxonomy_service_request(category_id, keyword)
    params = {'categoryId' => category_id,
              'keyword' => keyword.strip}
    make_api_request('taxonomy', params)
  end

  # make any API request given a hash of querystring parameter/values.  Generic parameters will be supplied.
  def make_api_request(service, service_params)
    params = {'apiKey' => 'ab77d51bc0001e8304f6269c29a3526a',
              'publisherId' => 3973,
              'placementId' => 1  # This is a value we can pass to
             }
    params = params.merge(service_params) # merge in the user params
    
    # sort 'em
    params = params.sort
    
    # build the querystring
    query_string = params.collect do |x|
      if x[1].class == Array
        x[1].collect{|y| "#{x[0]}=#{y}" }.join '&'
      else
        "#{x[0]}=#{x[1]}"
      end
    end.join('&')

    # do we already have a cached version of this API call?
    key = "shopping-api-#{Digest::MD5.hexdigest(query_string)}-v3"
    result = CACHE.get(key)
    if !result # nope.. gotta get a new one.
      url = "http://catalog.bizrate.com/services/catalog/v1/us/#{service}?#{query_string}"
      #puts "shopzilla.com API request URL: #{url}"
      begin
        result = timeout(api_call_timeout || @@default_api_call_timeout) do
          open(url)
        end
        result = result.read if result
        
        CACHE.set(key, result, Source.shopzilla_source.offer_ttl_seconds)
      rescue Timeout::Error
        @logger.warn "Shopzilla API call timed out: #{url}"
        result = nil
      rescue Exception => ex
        @logger.warn "Shopzilla API call failed (#{ex.message}): #{url}"
        result = nil
      end
    end
    if result
      Hpricot.XML(result)
    else
      nil
    end
  end

  def verify_logo_url(logo_url)
    begin
      open(logo_url, 'rb').close
      return true
    rescue Exception => ex
      puts "Not using bad merchant logo URL #{logo_url}: #{ex.message}"
      return false
    end
  end

  def safe_inner_text(element)
    element.nil? ? nil : element.inner_text
  end

  def safe_unescape_html(text)
    text.nil? ? nil : CGI::unescapeHTML(text)
  end

  def is_likely_new_condition?(condition_text)
    condition_text.blank? || condition_text.upcase == 'NEW' || condition_text.upcase == 'OEM'
  end

  def is_likely_in_stock?(stock_text)
    stock_text.blank? || stock_text.upcase != 'OUT'
  end

  def get_price_from_node(element)
    price = element.attributes['integral']
    price.blank? ? nil : (price.to_i / 100.0).to_d
  end
end
