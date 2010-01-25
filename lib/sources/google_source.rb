require 'uri'
require 'ostruct'
require 'open-uri'
require 'hpricot'

class GoogleSource < Source
  def initialize
    super(:name => 'Google Shopping',
          :homepage => 'http://www.google.com/products',
          :cpc => 0,
          :offer_enabled => false,
          :offer_ttl_seconds => 0,
          :use_for_merchant_ratings => true,
          :offer_affiliate => false,
          :supports_lifetime_ratings => false,
          :batch_fetch_delay => 3,
          :product_code_regexp => nil,
          :product_code_examples => [])
  end
  
  def url_for_merchant_source_page(merchant_source_code)
    "http://www.google.com/products/reviews?sort=1&cid=#{merchant_source_code}"
  end

  def code_from_merchant_source_page_url(merchant_source_page_url)
    merchant_source_page_url.match /google.com.*cid=(.+?)($|&.*)/
    $1
  end

  def fetch_merchant_source(merchant_source_page_url)
    delay_fetch
    doc = Hpricot(open(merchant_source_page_url))

    merchant_source = OpenStruct.new
    merchant_source.source = self

    # merchant code
    code = code_from_merchant_source_page_url(merchant_source_page_url)
    merchant_source.code = code

    # merchant name
    element = doc.at('//table//tr/td//font[@size = "+1"]')
    unless element.nil?
      name = element.inner_text.strip
      merchant_source.name = name
    end

    rating_box_element = doc.at('//table//tr//td//b[text() = "Average rating"]/..')

    # merchant rating
    element = rating_box_element.at('font[@size = "+3"]')
    unless element.nil?
      merchant_rating = element.inner_text.match(/\s*(.*?)\s*\/.*?/)[1]
      merchant_source.merchant_rating = merchant_rating.to_f * 20.0 unless merchant_rating.nil?
    end

    # Num Merchant Reviews
    element = rating_box_element.at('font[@size = "-1"]')
    unless element.nil?
      num_merchant_reviews = element.inner_text.match(/((\d|,)+)/)[1]
      merchant_source.num_merchant_reviews = num_merchant_reviews.delete(',').to_i unless num_merchant_reviews.nil? || num_merchant_reviews.empty?
    end

    merchant_source
  end

  def format_rating(merchant_source)
    '%01.1f/5.0' % (merchant_source.get_merchant_rating.to_f / 20.0)
  end

  def self.grab_new_mappings(google_merchant_list_url)
    #google_merchant_list_url = "http://www.google.com/products/catalog?q=Projectors&btnG=Search+Products&show=dd&cid=8852330310663509594&sa=N&start=0#ps-sellers"
    body = open(google_merchant_list_url)
    doc = Hpricot.XML(body)

    google_sellers = []
    sellers_table = (doc / '#ps-sellers-table')
    sellers_table.search('td.ps-seller-col').each_with_index do |sellers_column, i|
      next if i == 0
#      puts "Seller's column: #{sellers_column}"
      link = sellers_column.at('a')
      unless link.nil?
        name = link.inner_text.strip
        puts "Seller: #{name}"
        if link.attributes['href'].match /\?q=http:\/\/(.+)\//
          domain = Merchant.parse_url_for_domain($1)
          puts "Domain: #{domain}"
        end
      end
      rating_link = sellers_column.next_sibling.at('a')
      code = rating_link.attributes['href'].match(/.*&cid=(.+)&.*/)[1] unless rating_link.nil?
      puts "CID: #{code}"
      puts '-----------------------------------------------------'
      google_sellers << {:name => name, :code => code, :domain => domain} unless domain.nil? || domain.empty? || code.nil? || code.empty?
    end

    new_mappings_count = 0
    google_source = GoogleSource.first
    google_sellers.each do |seller|
      merchants = Merchant.find(:all, :conditions => {:domain => seller[:domain]})
      if merchants.length > 1
        puts "More than one merchant found for domain: #{seller[:domain]}"
      elsif merchants.length == 1
        merchant = merchants.first
        if merchant.merchant_source(google_source).nil?
          url = google_source.url_for_merchant_source_page(seller[:code])
          new_merchant_source = google_source.fetch_merchant_source(url)
          merchant.merchant_sources << new_merchant_source
          merchant.update_from_sources
          merchant.save!
          new_mappings_count += 1
        end
      end
    end
    puts "Google sellers found: #{google_sellers.length}"
    puts "New mappings added: #{new_mappings_count}"
    new_mappings_count
  end
end
