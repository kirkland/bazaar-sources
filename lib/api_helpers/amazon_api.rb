require 'hpricot'
require 'open-uri'
require 'cgi'
require 'hmac-sha2'

module AmazonAPI
  def self.associate_tag
    AMAZON_ASSOCIATE_TAG
  end

  def self.at_a_glance_url(seller_id)
    "http://www.amazon.com/gp/help/seller/at-a-glance.html?seller=#{seller_id}"
  end

  def self.offer_url(asin, merchant_type, merchant_id)
    "http://www.amazon.com/exec/obidos/ASIN/#{asin}/?#{merchant_type == 'seller' ? 'seller' : 'm'}=#{merchant_id}&tag=#{associate_tag}"
  end

  def self.offer_listing_url(asin)
    "http://www.amazon.com/gp/offer-listing/#{asin}?condition=new"
  end

  def self.find_offer_listing_id_by_asin_and_merchant_name(asin, merchant_name)
    offers = findOffersByASIN(asin)
    match = PseudoFuzzyMatching::match_string_in_array(offers.collect{|key,val| val.merchant_name}, merchant_name)
    if !match.blank?
      offers.find{|key,val| val.merchant_name == match}[1].offer_id
    else
      ''
    end
  end

  # reveal a too low to display price by adding it to the cart
  # returns the amount (in pennies) and the formatted price
  def self.reveal_too_low_to_display_price_from_offer_listing_id offer_listing_id
    request = {'Operation' => 'CartCreate',
               'AssociateTag' => AMAZON_ASSOCIATE_TAG,
               'Item.1.OfferListingId' => offer_listing_id,
               'Item.1.Quantity' => 1}
    req = make_amazon_api_request request
    formatted_price = (req / 'Cart' / 'CartItems' / 'SubTotal' / 'FormattedPrice').inner_html
    unformatted_price = (req / 'Cart' / 'CartItems' / 'SubTotal' / 'Amount').inner_html
    [unformatted_price, formatted_price]
  end
  
  def self.findOffersByASIN(asin, featured_merchants_only=false)
    asin.strip!
    request = {'Operation' => 'ItemLookup',
               'ResponseGroup' => 'Large,OfferFull',
               'ItemId' => asin,
               'IdType' => 'ASIN',
               'MerchantId' => featured_merchants_only ? 'Featured' : 'All',
               'Condition' => 'New',
               'OfferPage' => 1}
    req = make_amazon_api_request request
    offers = {}
    
    total_offer_pages = (req / 'Items' / 'Offers' / 'TotalOfferPages').inner_html.to_i
    
    #enumerate through all the offer pages    
    1.upto(total_offer_pages) do |page|
      # move on to the next page if necessary
      # (this helps avoid a repeat request)
      if page != 1
        request['OfferPage']+=1
        req = make_amazon_api_request request
      end
      
      #loop through all the offers
      (req / 'Items' / 'Offers' / 'Offer' ).each do |offer|
        # find either ther seller id or the merchant id
        
        id = (offer / 'Merchant' / 'MerchantId').inner_html
        if id.blank?
          id = (offer / 'Seller' / 'SellerId').inner_html
          name = (offer / 'Seller' / 'Nickname').inner_html
          type = 'seller'
        else
          name = (offer / 'Merchant' / 'Name').inner_html
          type = 'merchant'
        end
        
        if (offer / 'OfferListing' / 'SalePrice').size > 0 # sometimes we get a SalePrice
          unformatted_price = (offer / 'OfferListing' / 'SalePrice' / 'Amount').inner_html
          formatted_price = (offer / 'OfferListing' / 'SalePrice' / 'FormattedPrice').inner_html
        else # most of the time we just get Price
          unformatted_price = (offer / 'OfferListing' / 'Price' / 'Amount').inner_html
          formatted_price = (offer / 'OfferListing' / 'Price' / 'FormattedPrice').inner_html
        end
        added_to_cart = false
        if formatted_price == 'Too low to display'
          offer_listing_id = (offer / 'OfferListing' / 'OfferListingId').inner_html
          unformatted_price, formatted_price = AmazonAPI.reveal_too_low_to_display_price_from_offer_listing_id(offer_listing_id)
          added_to_cart = true
        end
        
        if (offer / 'OfferListing' / 'Quantity')
          quantity = (offer / 'OfferListing' / 'Quantity').inner_html.to_i
        end
        
        if !unformatted_price.blank?
          price = unformatted_price.to_i * 0.01 # convert 21995 to 219.95
        elsif !formatted_price.blank?  # sometimes we only get a formatted price and no amount
          price = formatted_price.gsub(/[$,]/,'').to_f 
        else
          price = 0.0 # should never get here.
        end

        offer_listing_id = (offer / 'OfferListing' / 'OfferListingId').inner_html
        total_feedback = (offer / 'Merchant' / 'TotalFeedback')

        if quantity.nil? || quantity > 0
          url = offer_url(asin, type, id)
          # do we already have it in the offers hash?
          # if so, we only want a lower price to override the entry.
          if !offers[id] || offers[id].price > price
            #add it to the offers hash
            offers[id] = ProductOffer.new({ :merchant_code => id,
                                            :merchant_name => CGI::unescapeHTML(name),
                                            :merchant_logo_url => nil,
                                            :cpc => nil,
                                            :price => BigDecimal(price.to_s),
                                            :shipping => nil,
                                            :offer_url => url,
                                            :offer_tier => type == 'seller' ? ProductOffer::OFFER_TIER_TWO : ProductOffer::OFFER_TIER_ONE,
                                            :merchant_type => type })
          end
        end
      end
    end
    offers
  end

  def fetch_all_new_offers_hash(product)
    findOffersForProduct(product, false)
  end

  def self.findOffersForProduct(product, featured_merchants_only=false)
    offer_array = []
    product.amazon_asins.each do |product_source|
      unless product_source.questionable?
        offer_array << scrape_offer_listing_page_to_hash(product_source.source_id, featured_merchants_only)
      end
    end
    offers = {}
    offer_array.each do |ha|
      next if ha.blank? # don't care if we didn't get any offers back...
      # only overwrite if the old price is greater than the new price.
      offers.merge!(ha) { |key, old_val, new_val| old_val.nil? || old_val.price > new_val.price ? new_val : old_val }
    end
    offers
  end

  def self.findProductByASIN(asin)
    request = {'Operation' => 'ItemLookup',
               'ResponseGroup' => 'Medium',
               'ItemId' => asin.strip,
               'IdType' => 'ASIN'}
    res = make_amazon_api_request request

    item = res / 'Items' / 'Item'
    asin = (item / 'ASIN').inner_html
    item_attributes = item / 'ItemAttributes'
    name = (item_attributes / 'Title').inner_html
    list_price = (item_attributes / 'ListPrice' / 'Amount').inner_html
    if list_price.blank?
      list_price = 0
    else
      list_price = (list_price.to_f / 100.0)
    end
    model = (item_attributes / 'Model').inner_html
    mpn = (item_attributes / 'MPN').inner_html
    upc = (item_attributes / 'UPC').inner_html
    manufacturer = (item_attributes / 'Manufacturer').inner_html
    begin
      small_image = {:url => (item.at('SmallImage') / 'URL').inner_html,
                     :width => (item.at('SmallImage') / 'Width').inner_html,
                     :height => (item.at('SmallImage') / 'Height').inner_html}
    rescue
      small_image = nil
    end
    begin
      medium_image = {:url => (item.at('MediumImage') / 'URL').inner_html,
                      :width => (item.at('MediumImage') / 'Width').inner_html,
                      :height => (item.at('MediumImage') / 'Height').inner_html}
    rescue
      medium_image = nil
    end
    begin
      large_image = {:url => (item.at('LargeImage') / 'URL').inner_html,
                     :width => (item.at('LargeImage') / 'Width').inner_html,
                     :height => (item.at('LargeImage') / 'Height').inner_html}
    rescue
      large_image = nil
    end

    product = {:asin => asin,
               :name => name,
               :list_price => list_price,
               :model => model,
               :mpn => mpn,
               :upc => upc,
               :manufacturer => manufacturer,
               :small_image => small_image,
               :medium_image => medium_image,
               :large_image => large_image}
    product
  end

  def self.itemSearch(searchTerms)
    request = {'Operation' => 'ItemSearch',
               'Keywords' => searchTerms,
               'SearchIndex' => 'All',
               'ResponseGroup' => 'Images,ItemAttributes'}
    res = make_amazon_api_request request
    products = []
    items = (res / 'Items' / 'Item')
    items.each do |item|
      begin
        small_image = item.at('SmallImage')
        if !small_image.blank?
          small_image_url = (small_image / 'URL').inner_html
        else
          small_image_url = ''
        end
        products << {
          :asin => (item / 'ASIN').inner_html,
          :name => (item / 'ItemAttributes' / 'Title').inner_html,
          :small_image_url => small_image_url
        }
      rescue
      end
    end
    products
  end

  def self.seller_lookup(seller_id)
    request = { 'Operation' => 'SellerLookup',
                'SellerId' => seller_id }
    res = make_amazon_api_request request

    element = res.at('/SellerLookupResponse/Sellers/Seller/SellerName')
    if element.nil?
      element = res.at('/SellerLookupResponse/Sellers/Seller/Nickname')
    end
    if !element.nil?
      merchant_name = element.inner_text
    end
    begin
      details = scrape_at_a_glance_page(seller_id)
      logo_url = details[:logo_url]
      merchant_name = details[:merchant_name] if merchant_name.blank?
      homepage = details[:homepage]
    rescue
    end

    if merchant_name.blank?
      merchant_name = "Amazon merchant (#{seller_id})"
    end

    element = res.at('/SellerLookupResponse/Sellers/Seller/GlancePage')
    glance_page_url = element.inner_text unless element.nil?

    element = res.at('/SellerLookupResponse/Sellers/Seller/AverageFeedbackRating')
    average_feedback_rating = element.nil? ? 0.0 : element.inner_text.to_f

    element = res.at('/SellerLookupResponse/Sellers/Seller/TotalFeedback')
    total_feedback = element.nil? ? 0 : element.inner_text.to_i

    { :seller_id => seller_id,
      :merchant_name => merchant_name,
      :glance_page_url => glance_page_url,
      :average_feedback_rating => average_feedback_rating,
      :total_feedback => total_feedback,
      :logo_url => logo_url,
      :homepage => homepage }
  end

  def self.scrape_at_a_glance_page(seller_id)
    url = at_a_glance_url(seller_id)
    doc = scrape_page(url, 10.minutes, 'seller')
    merchant_description_box_element = doc.at('//table//tr//td//h1[@class = "sans"]/strong/../..')

    unless merchant_description_box_element.nil?
      element = merchant_description_box_element.at('//h1/strong')
      merchant_name = element.inner_text.strip unless element.nil?

      element = merchant_description_box_element.at('//img')
      merchant_logo_url = element.attributes['src'] unless element.nil?
    end

    homepage_link = doc.at('//tr[@class = "tiny"]/td/a[@target = "_blank" and @href = text()]')
    homepage = homepage_link.inner_text unless homepage_link.nil?

    { :merchant_name => merchant_name,
      :logo_url => merchant_logo_url,
      :homepage => homepage }
  end

  def self.scrape_offer_listing_page_to_hash(asin, featured_merchants_only=false)
    offers_hash = {}
    offers = scrape_offer_listing_page(asin, featured_merchants_only)
    offers.each do |offer|
      offers_hash[offer.merchant_code] = offer
    end
    offers_hash
  end

  def self.scrape_offer_listing_page(asin, featured_merchants_only=false)
    offers = []
    url = offer_listing_url(asin)
    begin
      doc = scrape_page(url, Source.amazon_source.offer_ttl_seconds / 2, 'offer-listing')
    rescue Net::HTTPServerException => ex
      if ex.message =~ /^404/
        ProductSource.increment_not_found_count(ProductSource::Name::AMAZON, asin)
      else
        puts "Unexpected HTTP error while scraping Amazon Offer Listing page for #{asin}: #{ex.message}"
      end
      return offers
    rescue Net::HTTPFatalError => ex
      ProductSource.increment_fatal_error_count(ProductSource::Name::AMAZON, asin)
      return offers
    end
    offers_box_element = doc.at('div.resultsset')
    offer_type_header_tables = offers_box_element.search('table.resultsheader')
    offer_type_header_tables.each do |offer_type_header_table|
      if offer_type_header_table.inner_text =~ /Featured Merchants/
        featured_offer_rows = offer_type_header_table.next_sibling.search('tbody.result/tr')
        offers += parse_offer_listing_rows(asin, featured_offer_rows, true)
      elsif !featured_merchants_only && offer_type_header_table.inner_text =~ /New/
        other_offer_rows = offer_type_header_table.next_sibling.search('tbody.result/tr')
        offers += parse_offer_listing_rows(asin, other_offer_rows, false)
      end
    end

#    offers.each_with_index do |offer, i|
#      puts "#{i+1}. --------------------------------------------------------------------"
#      puts "Merchant: #{offer[:name]} (#{offer[:merchant_id]})#{' FEATURED' if offer[:featured_merchant]}"
#      puts "Merchant logo URL: #{offer[:merchant_logo_url]}" unless offer[:merchant_logo_url].nil?
#      puts "Price/Shipping: #{offer[:price]}/#{offer[:shipping]}"
#      puts "Offer ID: #{offer[:offer_id]}"
#      puts "Offer URL: #{offer[:offer_url]}"
#      puts "Merchant type: #{offer[:merchant_type]}"
#      puts "Had to add to cart to get price." if offer[:added_to_cart]
#      if offer[:merchant_id].nil? || offer[:name].nil? ||
#         offer[:price].nil? || offer[:shipping].nil? ||
#          offer[:offer_id].nil? || offer[:offer_url].nil?
#        puts "!!!! One or more fields not parsed correctly !!!!"
#      end
#      puts '-----------------------------------------------------------------------'
#    end
    offers
  end

  def self.parse_offer_listing_rows(asin, offer_listing_rows, featured_merchants)
    offers = []
    offer_listing_rows.each_with_index do |row, i|
      # Offer Listing ID
      offer_listing_tag = row.at("td.readytobuy/form/input[@name *= 'offering-id.']")
      unless offer_listing_tag.nil?
        offer_listing_id = offer_listing_tag.attributes['name'].sub('offering-id.', '')
      end

      # Price
      added_to_cart = false
      price_element = row.at("span.price")
      unless price_element.nil?
        price = price_to_f(price_element.inner_text)
      end
      add_to_cart_span = row.at("td/span[text() *= 'Add to cart to see price.']")
      if add_to_cart_span && !offer_listing_id.blank?
        price = price_to_f(reveal_too_low_to_display_price_from_offer_listing_id(offer_listing_id).second)
        added_to_cart = true
      end
      if price.nil?
        ExceptionNotifier.notify(:error_class => 'AmazonAPI Error',
                                 :error_message => 'Failed to find price while scraping the offer listing page.',
                                 :request => { :params => {:asin => asin, :featured_merchants => featured_merchants, :row => row.inner_text }})
        next
      end

      # Shipping
      shipping_element = row.at("div.shipping_block/span.price_shipping")
      if shipping_element.nil?
        super_saver_element = row.at("span.supersaver")
        shipping = 0.0 unless super_saver_element.nil?
      else
        shipping = price_to_f(shipping_element.inner_text)
      end

      seller_info = row.at("td[/ul.sellerInformation]")
      unless seller_info.nil?
        # Seller ID, merchant rating, and num merchant reviews
        seller_id = nil
        merchant_rating = nil
        num_merchant_reviews = nil
        rating_block = seller_info.at("div.rating")
        unless rating_block.nil?
          rating_text = rating_block.inner_text
          if rating_text =~ /\((\d+) ratings\.\)/
            num_merchant_reviews = $1.to_i
          end
        end
        rating_link = seller_info.at("div.rating/a")
        unless rating_link.nil?
          seller_id = rating_link.attributes['href'].match(/seller=([^&#]+)/)[1]
          merchant_rating = rating_link.inner_text.to_i
        end
        if seller_id.nil?
          shipping_rates_link = seller_info.at("div.availability/a[text() = 'Shipping Rates']")
          unless shipping_rates_link.nil?
            if shipping_rates_link.attributes['href'].match(/seller=([^&#]+)/)
              seller_id = $1
            end
          end
        end
        if seller_id.nil?
          seller_profile_link = seller_info.at("div.rating//a[text() = 'Seller Profile']")
          unless seller_profile_link.nil?
            if seller_profile_link.attributes['href'].match(/seller=([^&#]+)/)
              seller_id = $1
            end
          end
        end
        if seller_id.nil?
          ExceptionNotifier.notify(:error_class => 'AmazonAPI Error',
                                   :error_message => 'Failed to find seller_id while scraping the offer listing page.',
                                   :request => { :params => {:asin => asin, :featured_merchants => featured_merchants, :seller_info => seller_info.inner_text }})
          next
        end

        # Seller's Name & logo URL
        merchant_type = 'merchant'
        seller_label_link = seller_info.at('div.seller/a')
        if seller_label_link.nil?
          seller_logo_img = seller_info.at('a/img')
          seller_logo_img = seller_info.at('img') if seller_logo_img.nil?
          unless seller_logo_img.nil?
            name = safe_strip(seller_logo_img.attributes['alt'])
            logo_url = seller_logo_img.attributes['src']
          end
        else
          name = safe_strip(seller_label_link.inner_text)
          merchant_type = 'seller'
        end

        # Availability
        in_stock = true
        availability_element = seller_info.at("div.availability")
        unless availability_element.nil?
          availability_info = availability_element.inner_text
          if availability_info.match(/out of stock/i)
            in_stock = false
          elsif availability_info.match(/Usually ships within .+ days/i)
            in_stock = true
          elsif availability_info.match(/Usually ships within .+ months/i)
            in_stock = false
          elsif availability_info.match(/In Stock/i)
            in_stock = true
          end
        end
      end

      if in_stock
        # Offer URL
        offer_url = offer_url(asin, merchant_type, seller_id)

        offers << ProductOffer.new({ :merchant_code => seller_id,
                                     :merchant_name => CGI::unescapeHTML(name),
                                     :merchant_logo_url => logo_url,
                                     :cpc => Source.amazon_source.cpc,
                                     :price => price.nil? ? nil : BigDecimal(price.to_s),
                                     :shipping => shipping.nil? ? nil : BigDecimal(shipping.to_s),
                                     :offer_url => offer_url,
                                     :offer_tier => featured_merchants ? ProductOffer::OFFER_TIER_ONE : ProductOffer::OFFER_TIER_THREE,
                                     :merchant_rating => merchant_rating,
                                     :num_merchant_reviews => num_merchant_reviews,
                                     :merchant_type => merchant_type })
      end
    end
    offers
  end

  private

  def self.scrape_page(url, cache_ttl, context_name=nil)
    # shoot off the request
    body = do_api_request(url)
    Hpricot(body)
  end

  # make any API request given a hash of querystring parameters
  def self.make_amazon_api_request(user_params)
    params = {'Service' => 'AWSECommerceService',
              'Version' => '2007-07-16',
              'AWSAccessKeyId' => AMAZON_ACCESS_KEY_ID}
    params = params.merge(user_params) # merge in the user params

    # because params is a hash, its order isn't defined.. so we sort it.
    # this converts it to an array, but that's okay.
    sorted_params_arr = params.sort{|a,b| a[0]<=>b[0]}
    # build the query string
    query_string = sorted_params_arr.collect{|x| "#{x[0]}=#{CGI::escape(CGI::unescape(x[1].to_s))}"}.join('&')

    # do we already have a cached version of this API call?
    key = "amazon-api-#{Digest::MD5.hexdigest(query_string)}-v2"
    result = CACHE.get(key)
    if !result # nope.. gotta get a new one.
      url = sign_url('ecs.amazonaws.com', '/onca/xml', params)
      # shoot off the request
      result = do_api_request(url)
      CACHE.set(key, result, Source.amazon_source.offer_ttl_seconds) # 1 hour
    end
    Hpricot.XML(result)
  end

  # create the Net::HTTP object to actually do the request
  def self.do_api_request(url, retry_num=0, max_retries=10)
    if retry_num >= max_retries
      raise StandardError, "Failed to get Amazon URL with after #{max_retries} tries for url: #{url.inspect}"      
    end
    
    #puts "Amazon API request URL: #{url}"
    req_url = URI.safe_parse(url)
    http = Net::HTTP.new(req_url.host, 80)
    http.read_timeout=5 # 5 second timeout
    resp = nil
    begin
      http.start do |web|
        resp = web.get("#{req_url.path}?#{req_url.query}")
      end
    rescue Timeout::Error
      # timed out, try again.
      retry_num += 1
      do_api_request(url, retry_num, max_retries)
    end
    
    case resp
    when Net::HTTPSuccess
      resp.body
    when Net::HTTPRedirection
      redirect_url = resp['location']
      retry_num += 1
      do_api_request(redirect_url, retry_num, max_retries)
    when Net::HTTPServiceUnavailable
      puts "GOT Net::HTTPServiceUnavailable FROM AMAZON; SLEEPING AND TRYING IN TWO SECONDS. RETRY NUM #{retry_num}."
      sleep(2)
      retry_num += 1
      do_api_request(url, retry_num, max_retries)
    when Net::HTTPClientError, Net::HTTPServerError
      puts "GOT #{resp.class.name} FROM AMAZON."
      resp.error!
    else
      raise StandardError, "Failed to get Amazon URL with unknown error: #{resp.inspect} For url: #{url.inspect}"
    end
  end

  def self.safe_strip(value)
    value.nil? ? nil : value.strip
  end

  def self.price_to_f(value)
    return nil if value.blank?
    value.gsub(/[^\d\.]/, '').match(/(\d*\.?\d+)/)[1].to_f rescue nil
  end

  def self.sign_url(host, path, params)
    timestamp = CGI::escape(Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
    params['Timestamp'] = timestamp
    params_string = params.sort{|a,b| a[0]<=>b[0]}.collect{|x| "#{x[0]}=#{CGI::escape(CGI::unescape(x[1].to_s))}"}.join('&')
    params_string.gsub!('+', '%20')

    query = "GET\n#{host}\n#{path}\n#{params_string}"

    hmac = HMAC::SHA256.digest(AMAZON_SECRET_ACCESS_KEY, query)
    base64_hmac = Base64.encode64(hmac).chomp
    signature = CGI::escape(base64_hmac)
    "http://#{host}#{path}?#{params_string}&Signature=#{signature}"
  end
end