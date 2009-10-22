module ShoppingAPI
  require 'hpricot'
  require 'open-uri'
  require 'cgi'
  
  class SearchType
    SHOPPING_PRODUCT_ID = 'SHOPPING_PRODUCT_ID'  # Shopping Product ID-based search
    PRODUCT = 'PRODUCT'  # Search by our products
    KEYWORDS = 'KEYWORDS'  # Search by a 1 or more keywords
  end

  def self.get_all_categories
    params = {
      'categoryId' => 0,
      'showAllDescendants' => true
    }
    result = make_v3_request :CategoryTree, params
    parse_category(result.at('category[@id="0"]'))
  end
  
  # parse a category, then look for sub-categories and parse those too!
  def self.parse_category(category, parent_id=nil)
    categories = []
    id = category.attributes['id'].to_i
    # main category, does not count as a parent and should not be added
    if id == 0
      name = nil
      id = nil
    else
      name = category.at('name').innerText
    end
    hash = {
      :banned => banned_categories.include?(name),
      :id => id,
      :name => name,
      :parent_id => parent_id
    }
    if sub_categories = category.at('categories')
      categories << hash.merge({:end_point => false}) unless name == nil || id == nil
      # if there are sub categories, we don't want to add the parent to the list
      # that we'll be searching.
      (sub_categories / '> category').each do |sub_category|
        categories += parse_category(sub_category, id)
      end
    else
      categories << hash.merge({:end_point => true})
    end
    
    categories
  end
  
  # batch lookup products
  # takes a search hash, which should have a :search_type key (one member from SearchType Enum above)
  # for searching products, pass an array of products in :products (:search_type => ShoppingAPI::SearchType::PRODUCT)
  # for searching from shopping product ids, pass an array of shopping product ids in :shopping_product_ids (:search_type => ShoppingAPI::SearchType::SHOPPING_PRODUCT_ID)
  # for those two above, you can pass :batch_lookup, which is how many we should look up w/ shopping at once
  # for searching a keyword, pass a :keywords array of strings (any you want to be included in results, ordered) (:search_type => ShoppingAPI::SearchType::KEYWORDS)
  def self.batch_search_v3(search_hash, sandbox=false)  
    search_hash[:batch_lookup] ||= 20
    
    case search_hash[:search_type]
    when SearchType::SHOPPING_PRODUCT_ID
      items = search_hash[:shopping_product_ids]
      search_hash[:get_extra_product_info] ||= false
    when SearchType::PRODUCT
      # list of shopping product ids to their associated product
      # useful to bring back the shopping_product_ids into products
      search_hash[:product_ids_hash] = search_hash[:products].inject({}) do |ha, product|
        shopping_product_source = product.shopping_ids.detect{|product_source| !product_source.source_id.blank? && !product_source.questionable?}
        unless shopping_product_source.nil?
          shopping_id = shopping_product_source.source_id
          if ha.has_key?(shopping_id)
            puts "DUPLICATE KEY FOR #{shopping_id} !! #{ha[shopping_id].inspect} VS #{product.id}"
          end
          ha[shopping_id] = product.id
        end
        ha
      end
      # just the shopping product ids
      search_hash[:product_ids] = search_hash[:product_ids_hash].keys
      items = search_hash[:product_ids]
      search_hash[:get_extra_product_info] ||= false
    when SearchType::KEYWORDS
      items = search_hash[:keywords]
      search_hash[:get_extra_product_info] = true # force extra info, how else will we get the name/etc. ?!
    else
      raise ArgumentError, "Invalid :search_type specified: #{search_hash[:search_type].inspect}"
    end
    
    # defaults
    all_offers = self.default_offers
    all_product_infos = self.default_product_infos(search_hash[:get_extra_product_info])
    missed_ids = []
    second_misses = []
    # puts "SEARCH HASH: #{search_hash.inspect}"
    # look 'em up in batches!
    items.each_slice(search_hash[:batch_lookup]) do |batch_items|
      search_hash[:batch_items] = batch_items
      misses, offers, product_infos = self.single_batch_search_v3(search_hash, sandbox)
      all_product_infos.update(product_infos)
      all_offers.update(offers)
      missed_ids += misses unless misses.blank?
    end
    
    # for the ones we missed, we're going to try looking them up one more time
    # before giving up entirely.
    # (only applies to non-category/keyword searches)
    if missed_ids.length > 0
      # now look up the missed IDs in their own batch
      missed_ids.each_slice(search_hash[:batch_lookup]) do |batch_items|
        search_hash[:batch_items] = batch_items
        misses, offers, product_infos = self.single_batch_search_v3(search_hash, sandbox)
        all_product_infos.update(product_infos)
        all_offers.update(offers)
        second_misses += misses unless misses.blank?
        offers = nil
        product_infos = nil
      end
    end
    
    # only care to look up one-by-one if we're going to do something with the data
    # (for product lookups, then, to hide or update shopping ids)
    if !second_misses.blank? && search_hash[:search_type] == SearchType::PRODUCT
      # missed again? gotta look up one-by-one!
      products_to_hide = []
      second_misses.each do |product_id|
        our_product_id = search_hash[:product_ids_hash][product_id]
        search_hash[:batch_items] = [product_id]
        final_miss, offers, product_infos = self.single_batch_search_v3(search_hash, sandbox)
        all_product_infos.update(product_infos)
        all_offers.update(offers)
        if !final_miss.blank?
          puts "****** COULDN'T LOOK UP INFO FOR #{our_product_id} ( SHOPPING ID #{product_id}) !! Adding to hide queue..."
          products_to_hide << product_id
        else
          # shopping gave us a product ID back that doesn't match our shopping product ID! gotta update!
          new_shopping_id = product_infos[our_product_id][:reported_product_id]
          if ps = ProductSource.find_by_source_name_and_source_id(ProductSource::Name::SHOPPING, new_shopping_id)
            puts "SHOPPING PRODUCT ID ALREADY EXISTS AT #{ps.product_id} -- HIDING DUPLICATE #{our_product_id}"
            products_to_hide << product_id
          else
            puts "UPDATING SOURCE ID: FROM #{product_id.inspect} TO #{new_shopping_id.inspect} FOR product id##{our_product_id}"
            ProductSource.update_all("source_id = E'#{new_shopping_id}'", "source_id = E'#{product_id}' AND product_id = #{our_product_id}")
          end
        end
      end
      puts "HIDING PRODUCTS: #{products_to_hide.inspect}"
      if products_to_hide.length > 0
        products_to_hide.each do |shopping_product_id|
          ProductSource.increment_not_found_count(ProductSource::Name::SHOPPING, shopping_product_id)
        end
      end
    end
    # return all that jazz
    [all_offers, all_product_infos]
  end
  
  # find a single batch of offers and shove them info all_offers hash
  # this is just a helper for batch_search_v3 and shouldn't be called directly
  # for looking up a whole lot of product offers, look at batch_search_v3 above
  def self.single_batch_search_v3(search_hash, sandbox=false)
    misses, offers, product_infos = do_search_v3(search_hash, sandbox)
            
    # turn shopping ids into product ids for the returned results ( both offers and product_infos )
    # (only if they initially gave us a set of products)
    if search_hash[:search_type] == SearchType::PRODUCT
      search_hash[:batch_items].each do |product_id|
        [offers, product_infos].each do |item|
          our_id = search_hash[:product_ids_hash][product_id]
          # if OUR product id is the same as shopping's, we don't delete. obvi.
          next if our_id == product_id
          if our_id.nil?
            puts "******** NIL FOR #{product_id}"
          end
          item[our_id] = item[product_id]
          item.delete(product_id)
        end
      end
    end
    [misses, offers, product_infos]
  end
  
  def self.default_offers
    Hash.new([]).clone
  end
  
  def self.default_product_infos get_extra_product_info
    # smart defaults for error handling
    if get_extra_product_info
      product_infos = Hash.new({
        :avg_secondary_cpcs => nil,
        :primary_cpc => nil,
        :reported_product_id => nil,
        :images => {},
        :manufacturer => nil,
        :name => nil,
        :description => nil
      })
    else # even if they don't ask for it! BAM!
      product_infos = Hash.new({
        :avg_secondary_cpcs => nil,
        :primary_cpc => nil,
        :reported_product_id => nil
      })
    end
    
    product_infos.clone
  end
  
  def self.do_search_v3(search_hash, sandbox=false)
    # defaults
    offers = self.default_offers
    product_infos = self.default_product_infos(search_hash[:get_extra_product_info])
    misses = []
    
    case search_hash[:search_type]
    when SearchType::PRODUCT, SearchType::SHOPPING_PRODUCT_ID
      search_hash[:batch_items].compact! # remove nils
      if search_hash[:batch_items].blank?
        # nothing to look for! dummy.
        puts "NO PRODUCT ID PASSED!"
        # return blanks
        return [misses, offers, product_infos]
      end
      params = {
        'productId' => search_hash[:batch_items],
        'showProductOffers' => true,
        'numOffersPerProduct' => 20
      }
    when SearchType::KEYWORDS
      params = {
        #'categoryId' => search_hash[:category],
        'keyword' => Array(search_hash[:keywords].collect{|x| CGI::escape(x) }), # can be an array, thass coo' wit me.
        'showProductOffers' => true,
        'pageNumber' => 1,
        'numItems' => search_hash[:num_items].blank? ? 1 : search_hash[:num_items],
        # 'productSortType' => 'price',
        # 'productSortOrder' => 'asc'
      }
    end
    
    result = make_v3_request :GeneralSearch, params, sandbox
    

    if search_hash[:search_type] == SearchType::PRODUCT || search_hash[:search_type] == SearchType::SHOPPING_PRODUCT_ID
      if search_hash[:batch_items].length == 1 && result.at('product')
        # if we're looking up one ID, it doesn't matter if the ID they returned doesn't match ours
        misses = []
      elsif result.at('product') # if we got ANY products back
        misses = search_hash[:batch_items] - (result / 'product').collect{|x| x.attributes['id']}
      else # probably an error happened
        misses = search_hash[:batch_items]
      end
    end
    
    errors = result.search('exception[@type=error]')
    if errors.length > 0
      # we got an error, or more than one!
      if (search_hash[:search_type] == SearchType::PRODUCT || search_hash[:search_type] == SearchType::SHOPPING_PRODUCT_ID) && search_hash[:batch_items].length == 1 && errors.length == 1 && errors.first.at('message').innerText == "Could not find ProductIDs #{search_hash[:batch_items].first}"
        # happens when we look up one product id and it's not a valid product id according to shopping. we ignore this kind of error.
      else
        puts "*** ERROR *** Could not look up offers by product ids:"
        errors.each do |error|
          puts " - #{error.at('message').innerText}"
        end
        # notify hoptoad of this shit!
        HoptoadNotifier.notify(
          :error_class => "ShoppingOfferError",
          :error_message => %{
            We got error(s) while trying to get the shopping offers! #{search_hash[:batch_items].inspect}
          },
          :request => { :params => Hash[*errors.collect{|x| ["Error ##{errors.index(x)}", x.at('message').innerText] }.flatten] }
        )
      end
      
      # return blanks
      return [misses, offers, product_infos]
    end
    
    (result / 'product').each do |product|
      product_id = product.attributes['id']
      if (search_hash[:search_type] == SearchType::PRODUCT || search_hash[:search_type] == SearchType::SHOPPING_PRODUCT_ID) 
        # this happens when they give us back an ID that we didn't ask for
        # (if we are only looking at one product, we don't care what ID they give us back,
        # we know it's the product we were looking for)
        if search_hash[:batch_items].length == 1 && !search_hash[:batch_items].include?(product_id)
          product_id = search_hash[:batch_items].first # revert back to the ID we asked for, we put the other in product_infos[x][:reported_product_id]
        elsif !search_hash[:batch_items].include?(product_id)
          # skip it, already included in the misses ( hopefully ... )
          next
        end
      end
      
      offers[product_id]={}
      product_infos[product_id] = {
        :reported_product_id => product.attributes['id'] # their reported ID doesn't necessarily match up with our ID
      }
      if search_hash[:get_extra_product_info]
        product_infos[product_id][:name] = product.at('name').innerText
        
        try_description = product.at('fullDescription').innerText
        if try_description.blank?
          try_description = product.at('shortDescription').innerText
        end
        product_infos[product_id][:description] = try_description.blank? ? '' : try_description[0...255]
          
        images = (product / 'images' / 'image[@available="true"]').collect{|x|
          {
            :width => x.attributes['width'].to_i,
            :height => x.attributes['height'].to_i,
            :url => x.at('sourceURL').innerText
          }
        }.sort_by{|x| x[:width] * x[:height] }
        
        product_infos[product_id][:images] = {
          :small_image => images[0],
          :medium_image => images[1],
          :large_image => images[2]
        }
          
        # possible_manufacturers = (product / 'offer > manufacturer').collect{|x| x.innerText}.compact.uniq
        # 
        # if possible_manufacturers.length == 1
        #   product_infos[product_id][:manufacturer] = possible_manufacturers.first # easy peasy lemon squezy
        # elsif possible_manufacturers.length > 1
        #   # figure out which manufacturer is the most popular
        #   manufacturers_popularity_index = possible_manufacturers.inject({}) {|ha, manufacturer| ha[manufacturer] ||= 0; ha[manufacturer] += 1; ha }
        #   product_infos[product_id][:manufacturer] = manufacturers_popularity_index.sort_by{|key, val| val }.last.first
        # else
        #   product_infos[product_id][:manufacturer] = nil # zip, zero, doodad :(
        # end
      end
      
      (product.at('offers') / 'offer').each do |offer|
        store = offer.at('store')
        store_hash = {
          :name => store.at('name').innerText,
          :trusted => store.attributes['trusted'] == "true",
          :id => store.attributes['id'].to_i,
          :authorized_reseller => store.attributes['authorizedReseller'] == "true"
        }
        store_logo = store.at('logo')
        if store_logo.attributes['available'] == "true"
          store_hash[:logo] = {
            :width => store_logo.attributes['width'],
            :height => store_logo.attributes['height'],
            :url => store_logo.at('sourceURL').innerText
          }
        else
          store_hash[:logo] = nil
        end

        # store rating
        store_rating = store.at('ratingInfo')
        store_hash[:rating] = {
          :number => store_rating.at('rating').nil? ? nil : normalize_merchant_rating(store_rating.at('rating').innerText.to_f),
          :count => store_rating.at('reviewCount').innerText.to_i,
          :url =>  store_rating.at('reviewURL').nil? ? nil : store_rating.at('reviewURL').innerText
        }
        shipping_info = offer.at('shippingCost').attributes['checkSite'] == "true" ? nil : to_d_or_nil(offer.at('shippingCost').innerText)
        price_info = to_d_or_nil(offer.at('basePrice').innerText)
        if shipping_info && price_info
          total_price = shipping_info + price_info
        else
          total_price = price_info
        end

        # in-stock
        stock_status = offer.at('stockStatus').innerText
        in_stock = stock_status != 'out-of-stock' && stock_status != 'back-order'

        if in_stock
          offers[product_id][store_hash[:id]] = { :merchant_code => store_hash[:id].to_s,
                                                  :merchant_name => store_hash[:name],
                                                  :merchant_logo_url => store_hash[:logo].nil? ? nil : store_hash[:logo][:url],
                                                  :cpc => offer.at('cpc').nil? ? nil : (offer.at('cpc').innerText.to_f*100).to_i,
                                                  :price => to_d_or_nil(offer.at('basePrice').innerText),
                                                  :shipping => offer.at('shippingCost').attributes['checkSite'] == "true" ? nil : to_d_or_nil(offer.at('shippingCost').innerText),
                                                  :offer_url => offer.at('offerURL').innerText,
                                                  :offer_tier => 1,
                                                  :merchant_rating => store_hash[:rating][:number],
                                                  :num_merchant_reviews => store_hash[:rating][:count] }
        end
      end
      # return an array, don't care about the hash. was used for dup checking.
      offers[product_id] = offers[product_id].values.sort_by{|x| x[:price] + (x[:shipping] || 0) }
    end
    
    [misses, offers, product_infos]
  end

  def self.normalize_merchant_rating(merchant_rating)
    merchant_rating.nil? ? nil : (merchant_rating * 20.0).round
  end

  # get any ol' random attribute from a shopping id
  # for instance, 'Screen Size' is a good'un.
  def self.get_attribute_from_shopping_id_v3 shopping_id, attribute
    product_info = find_by_product_id_v3 shopping_id
    values = product_info[:specifications].values.flatten
    index = values.index(attribute)
    # we +1 here because the flattened values are [name, value] oriented
    index.nil? ? nil : values[index+1]
  end
  
  def self.parse_images_v3 images_element
    images_element.inject({}) do |ha,obj|
      ha["#{obj.attributes['width']}x#{obj.attributes['height']}"] = [obj.attributes['available'] == 'true', obj.at('sourceURL').innerText]
      ha
    end
  end
  
  def self.find_related_terms_v3 keyword, sandbox=false
     result = make_v3_request :GeneralSearch, {'keyword' => keyword}, sandbox
     (result / 'relatedTerms > term').collect{|x| x.innerText}
  end

  private

  def self.make_v3_request(action, user_params, sandbox=false)
    params = {
      'trackingId' => '8039097',
      'apiKey'     => '21e3f349-c5f4-4783-8354-6ff75371ae22'
    }
    params = params.merge(user_params) # merge in the user params
    # sort 'em for the caching
    params = params.sort
    
    query_string = params.collect{|x|
      if x[1].class == Array
        x[1].collect{|y| "#{x[0]}=#{y}" }.join '&'
      else
        "#{x[0]}=#{x[1]}"
      end
    }.join "&" # build the api url
    
    # do we already have a cached version of this API call?
    # key = "shopping-api-v3-#{action}-#{sandbox}-#{Digest::MD5.hexdigest(query_string)}-v2"    
    #result = CACHE.get(key)
    #if !result # nope.. gotta get a new one.
      url = sandbox ? "http://sandbox.api.shopping.com/publisher/3.0/rest/#{action}?#{query_string}" : "http://publisher.api.shopping.com/publisher/3.0/rest/#{action}?#{query_string}"
      # puts "Shopping.com API request URL: #{url}"
      result = do_api_request(url)
      #begin
      #  CACHE.set(key, result, Source.shopping_source.offer_ttl_seconds)
      #rescue MemCache::MemCacheError => e
      #  raise e unless e.message == 'Value too large, memcached can only store 1MB of data per key'
      #end
    #end
    Hpricot.XML(result)
  end

  # create the Net::HTTP object to actually do the request
  def self.do_api_request(url, retry_num=0, max_retries=4)
    # print '~.~'
    if retry_num >= max_retries
      raise StandardError, "Failed to get Shopping URL with after #{max_retries} tries for url: #{url.inspect}"
    end

    req_url = URI.safe_parse(url)
    http = Net::HTTP.new(req_url.host, req_url.port)
    http.read_timeout = 5 # 5 second timeout
    resp = nil
    begin
      http.start do |web|
        resp = web.get("#{req_url.path}?#{req_url.query}")
      end
    rescue Timeout::Error, Errno::EPIPE, Errno::ECONNRESET
      puts "Timeout, broken pipe, or connection reset. Trying again."
      # timed out, try again.
      retry_num += 1
      do_api_request(url, retry_num, max_retries)
    end

    case resp
    when Net::HTTPSuccess, Net::HTTPRedirection
      resp.body
    when Net::HTTPInternalServerError
      puts "GOT Net::HTTPInternalServerError FROM Shopping; SLEEPING AND TRYING IN 0.5 SECONDS. RETRY NUM #{retry_num}."
      sleep(0.5)
      retry_num += 1
      do_api_request(url, retry_num, max_retries)
    when Net::HTTPServiceUnavailable
      puts "GOT Net::HTTPServiceUnavailable FROM Shopping; SLEEPING AND TRYING IN TWO SECONDS. RETRY NUM #{retry_num}."
      sleep(2)
      retry_num += 1
      do_api_request(url, retry_num, max_retries)
    when nil
      puts "GOT nil FROM Shopping; SLEEPING AND TRYING IN 0.5 SECONDS. RETRY NUM #{retry_num}."
      sleep(0.5)
      retry_num += 1
      do_api_request(url, retry_num, max_retries)
    else
      raise StandardError, "Failed to get Shopping URL with unknown error: #{resp.inspect} For url: #{url.inspect}"
    end
  end

  def self.to_i_or_nil(value)
    value.blank? ? nil : value.strip.to_i rescue nil
  end

  def self.to_d_or_nil(value)
    value.blank? ? nil : BigDecimal(value.strip) rescue nil
  end
end
