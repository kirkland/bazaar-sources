require 'ostruct'
require 'hpricot'
require 'open-uri'
require 'csv'

module ShopCartUsaAPI
  def self.fetch_merchant_source(merchant_source_page_url)
    doc = Hpricot(open(merchant_source_page_url))
    convert_merchant_page_to_merchant_source(doc)
  end

  def self.find_offers_by_product_id(shopping_product_id)
    params = {'sku' => "CDS:#{shopping_product_id}"}
    result = make_api_request(params)
    offers = {}
    unless result.nil?
      (result / 'merchant').each do |offer|
        merchant_id = (offer / 'merchant_id').inner_html
        merchant_name = (offer / 'merchant_name').inner_html
        merchant_logo = (offer / 'merchant_logo').inner_html
        unless merchant_logo.nil?
          merchant_logo.match /(http:\/\/.+?\.gif|jpg)/i
          merchant_logo = $1
        end
        base_price = BigDecimal((offer / 'base_price').inner_html)
        if base_price.zero?
          puts "ShopCartUSA just sent us an offer of $0.00 for #{shopping_product_id}.  Rejected."
          next
        end
        cpc = (offer / 'cpc').inner_html
        cpc = (cpc.to_f.round(2) * 85).to_i unless cpc.nil? rescue nil # Our current keep-amount is 85%
        buy_url = (offer / 'buy_url').inner_html
        in_stock = (offer / 'in_stock').inner_html
        if in_stock != 'no'
          offers[merchant_id] = { :merchant_code => merchant_id,
                                  :merchant_name => merchant_name,
                                  :merchant_logo_url => merchant_logo,
                                  :cpc => cpc,
                                  :price => base_price,
                                  :shipping => nil,
                                  :offer_url => CGI::unescapeHTML(buy_url),
                                  :offer_tier => 1 }
        end
      end
    end
    offers.values
  end

  def self.find_problem_products
    bad_shopping_product_ids = []
    products = Product.find(:all, :conditions => "shopping_product_id != ''", :order => "shopping_product_id ASC")
    puts "There are #{products.length} products to be processed..."
    products.each do |product|
      begin
        url = "http://xml.shopcartusa.com/comparexml.asp?sku=CDS:#{product.shopping_product_id}&s=id1"
        puts "Shopping Product ID: #{product.shopping_product_id}"
        open(url)
      rescue Exception => ex
        if ex.message.match /500 Internal Server Error/
          bad_shopping_product_ids << product.shopping_product_id
        else
          Logger.new(STDERR).error "ShopCartUSA API error -> #{ex.message}; URL -> #{url}"
        end
      end
      sleep 1
    end
    puts "Done."
    puts "Bad Shopping Product IDs:"
    bad_shopping_product_ids.each { |id| puts id.to_s }
    nil
  end

  def self.import_merchants_from_csv(csv_file_path, remove_existing_if_not_found=false)
    known_merchants = {}
    Merchant.find(:all).each do |merchant|
      unless merchant.name.nil? || merchant.name.empty?
        merchant_name = normalize_merchant_name(merchant.name)
        if known_merchants.has_key? merchant_name
          puts "Duplicate merchant name found: #{merchant_name}"
        end
        if merchant_name.empty?
          puts "Normalized merchant name came out blank: #{merchant.name}"
        end
        known_merchants[merchant_name] = merchant
      end
    end
#    pp known_merchants.keys.sort

    incoming_merchants = {}
    incoming_merchant_codes = []
    CSV.foreach(csv_file_path) do |row|
      merchant_code = row[0].strip
      incoming_merchant_codes << merchant_code
      merchant_name = row[1].strip
      normalized_merchant_name = normalize_merchant_name(merchant_name)
      unless normalized_merchant_name.empty?
        new_merchant_source = OpenStruct.new
        new_merchant_source.name = merchant_name
        new_merchant_source.code = merchant_code
        incoming_merchants[normalized_merchant_name] = new_merchant_source
      end
    end
#    pp incoming_merchants.keys.sort

    shop_cart_usa_source = Source.shop_cart_usa_source

    match_count = 0
    new_sources_count = 0
    incoming_merchants.each do |incoming_merchant_name, new_merchant_source|
      if known_merchants.has_key? incoming_merchant_name
        known_merchant = known_merchants[incoming_merchant_name]
        match_count += 1
        if MerchantSource.find_by_source_and_code(shop_cart_usa_source, new_merchant_source.code).nil?
          new_merchant_source.source = shop_cart_usa_source
          new_merchant_source.merchant = known_merchant
          new_merchant_source.save!
          new_sources_count += 1
        end
      end
    end

    if remove_existing_if_not_found
      old_mappings = 0
      shop_cart_usa_source.merchant_sources.each do |merchant_source|
        if !incoming_merchant_codes.include?(merchant_source.code)
          puts "Removing old mapping: #{merchant_source.name} (#{merchant_source.code})"
          merchant_source.destroy
          old_mappings += 1
        end
      end
    end

    puts "Existing merchants: #{known_merchants.size}"
    puts "Incoming merchants: #{incoming_merchants.size}"
    puts "Matches found: #{match_count}"
    puts "New merchant sources created: #{new_sources_count}"
    puts "Old merchant sources removed: #{old_mappings}" if remove_existing_if_not_found
    nil
  end

  def self.normalize_merchant_name(merchant_name)
    normalized_name = merchant_name.downcase
    normalized_name.gsub!(/ \/ .+/, '')
    normalized_name.gsub!(/http:\/\/|www\.|\.com$|\.net$/, '')
    normalized_name.gsub!(/\(.*\)/, '')
    normalized_name.gsub!(/\[.*\]/, '')
    normalized_name.gsub!(/(\.|_| )inc(\.|)| llc(\.|)| intl(\.|)/, '')
    normalized_name.gsub!(/[\s\-_,\.'\\"]|\.com$/, '')
    normalized_name
  end

  # -----------------------------------------------------------------------------------------------
  private
  # -----------------------------------------------------------------------------------------------

  def self.convert_merchant_page_to_merchant_source(merchant_source_doc)
    merchant_source = OpenStruct.new
    merchant_source.source = Source.shop_cart_usa_source

    # Merchant Code
    elements = merchant_source_doc.search('input[@name="clientid"]')
    unless elements.empty?
      code = elements.first.attributes['value']
      merchant_source.code = code
    end

    # Use a blank 'code' to indicate we didn't find the merchant page
    if merchant_source.code.nil? || merchant_source.code.empty?
      return nil
    end

    # Merchant Name
    element = merchant_source_doc.at('/html/head/title')
    unless element.nil?
      name = element.inner_text
      name = $1 if name.match /^(.+?) - .*/
      name = $1 if name.match /^(.+) Reviews$/
      merchant_source.name = name.strip
    end

    # Merchant Homepage
    element = merchant_source_doc.search('a[@class="bodytext"]/strong')
    unless element.nil?
      homepage = element.inner_html.strip
      if homepage !~ /^http(s|):\/\//i
        homepage = "http://#{homepage}"
      end 
      merchant_source.homepage = homepage
    end

    merchant_source
  end

  # make any API request given a hash of querystring parameters
  def self.make_api_request(context_params)
    params = {'s' => 'id1'}
    params = params.merge(context_params) # merge in the user params
    
    # sort the params
    params = params.sort
    
    # build the query string
    query_string = params.collect{|x| "#{x[0]}=#{CGI::escape(CGI::unescape(x[1].to_s))}"}.join '&'
    
    # do we already have a cached version of this API call?
    key = "shopcartusa-api-#{Digest::MD5.hexdigest(query_string)}-v2"
    result = CACHE.get(key)
    if !result # nope.. gotta get a new one.
      url = "http://xml.shopcartusa.com/comparexml.asp?#{query_string}"
      # puts "ShopCartUSA.com API request URL: #{url}"
      begin
        result = open(url).read
        CACHE.set(key, result, Source.shop_cart_usa_source.offer_ttl_seconds)
      rescue Exception => ex
        Logger.new(STDERR).error "*** WARNING *** ShopCartUSA API error -> #{ex.message}; URL -> #{url}"
        result = nil
      end
    end
    Hpricot.XML(result) unless result.nil?
  end
end
