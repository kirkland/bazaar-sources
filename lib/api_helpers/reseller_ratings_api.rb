require 'ostruct'
require 'hpricot'
require 'api_helpers/external_url'

module ResellerRatingsAPI
  def self.alt_code_from_merchant_source_page_url(merchant_source_page_url)
    alt_code = nil
    if res = merchant_source_page_url.match(/resellerratings\.com\/store\/([^\/\?#]*)/)
      alt_code = res[1]
    end
    alt_code
  end

  def self.fetch_suggestions(search_text, limit)
    rr_search_url = "http://www.resellerratings.com/reseller_list.pl?keyword_search=#{URI.escape(search_text)}"
    doc_and_final_uri = open_doc(rr_search_url)
    result = []
    unless doc_and_final_uri.nil? || doc_and_final_uri[:final_uri].nil? || doc_and_final_uri[:final_uri].empty?
      final_uri = URI.safe_parse(doc_and_final_uri[:final_uri])
      if final_uri.path == '/reseller_list.pl'
        # got the search results page with more than one result
        result = convert_search_results_page_to_merchant_array(doc_and_final_uri[:doc], limit)
      elsif final_uri.path.match(/^\/store\/(.+)$/)
        # got merchant page back
        result << { :merchant_page_url => final_uri, :merchant_code => $1, :merchant_name => $1.gsub('_', ' ') }
      else
        # don't know where we ended up
      end
    end
    result
  end

  def self.search_for_merchant_source(search_text, limit=15)
    merchant_sources = []
    rr_search_url = "http://www.resellerratings.com/reseller_list.pl?keyword_search=#{URI.escape(search_text)}"
    doc_and_final_uri = open_doc(rr_search_url)
    unless doc_and_final_uri.nil?
      if merchant_page_url?(doc_and_final_uri[:final_uri])
        merchant_sources << convert_merchant_page_to_merchant_source(doc_and_final_uri)
      else
        doc_and_final_uri[:doc].search('tr/td/font/a[text() = "Read Reviews"]/../../..').each do |result_row|
          element = result_row.at('td//a')
          name = element.inner_text.strip
          alt_merchant_code = element.attributes['href'].match(/\/store\/(.+)$/)[1]
          existing_merchant_source = MerchantSource.find_by_source_and_alt_code(Source.reseller_ratings_source, alt_merchant_code)
          if existing_merchant_source.nil?
            merchant_sources << OpenStruct.new({:source => Source.reseller_ratings_source, :name => name, :alt_code => alt_merchant_code})
          else
            merchant_sources << existing_merchant_source
          end
          break if merchant_sources.length >= limit
        end
      end
    end
    merchant_sources
  end

  def self.search_for_merchant_source_best_match(search_text)
    rr_search_url = "http://www.resellerratings.com/reseller_list.pl?keyword_search=#{URI.escape(search_text)}"
    fetch_merchant_source(rr_search_url)
  end

  def self.fetch_merchant_source(merchant_source_page_url)
    doc_and_final_uri = open_doc(merchant_source_page_url)
    if !doc_and_final_uri.nil?
      convert_merchant_page_to_merchant_source(doc_and_final_uri)
    else
      nil
    end
  end

  def self.fetch_merchant_source_by_alt_merchant_code(alt_merchant_code)
    merchant_source_page_url = "http://www.resellerratings.com/store/#{alt_merchant_code}"
    fetch_merchant_source(merchant_source_page_url)
  end

  def self.merchant_page_url?(url)
    !url.nil? && url.match(/\/store\/.+$/) != nil
  end

  private

  def self.convert_merchant_page_to_merchant_source(doc_and_final_uri)
    return nil if doc_and_final_uri.nil?
    merchant_source = OpenStruct.new
    merchant_source.source = Source.reseller_ratings_source
    doc = doc_and_final_uri[:doc]

    # Merchant Code
    elements = doc.search('img[@src="http://images.resellerratings.com/images/write_a_review.gif"]/..')
    unless elements.empty?
      code = elements.first[:href].match(/^.*?([0-9]+).*?$/)[1]
      merchant_source.code = code
    end

    # Use a blank 'code' to indicate we didn't find the merchant page
    if merchant_source.code.nil? || merchant_source.code.empty?
      return nil
    end

    # Alternative Merchant Code
    unless doc_and_final_uri[:final_uri].nil? || doc_and_final_uri[:final_uri].empty?
      merchant_source.alt_code = alt_code_from_merchant_source_page_url(doc_and_final_uri[:final_uri])
    end

    # Merchant Name
    elements = doc.search('img[@src="http://images.resellerratings.com/images/small-storefront-rev.gif"]/../..')
    unless elements.empty?
      name = elements.first.inner_text.strip
      merchant_source.name = name
    end

    # Merchant Homepage
    elements = doc.search('font[text() *= "Homepage:"]/a/font')
    unless elements.empty?
      homepage = elements.first.inner_text.strip
      merchant_source.homepage = homepage
    end

    # Merchant Rating
    elements = doc.search('font[text() *= "Six-Month Rating:"]/../font[2]')
    unless elements.empty?
      merchant_rating = elements.first.inner_text.match(/\s*(.*?)\s*\/.*?/)[1]
      merchant_source.merchant_rating = (merchant_rating.to_f * 10.0).round unless merchant_rating.nil?
    end

    # Num Merchant Reviews
    elements = doc.search('font[text() *= "Six-Month Reviews:"]/../../td[2]')
    unless elements.empty?
      num_merchant_reviews = elements.first.inner_text.strip
      merchant_source.num_merchant_reviews = num_merchant_reviews
    end

    # Merchant Rating Lifetime
    elements = doc.search('font[text() *= "Lifetime Rating:"]/../font[2]')
    unless elements.empty?
      merchant_rating_lifetime = elements.first.inner_text.match(/\s*(.*?)\s*\/.*?/)[1]
      merchant_source.merchant_rating_lifetime = (merchant_rating_lifetime.to_f * 10.0).round unless merchant_rating_lifetime.nil?
    end

    # Num Merchant Reviews Lifetime
    elements = doc.search("font[text() *= 'Lifetime\nReviews:']/../../td[2]")
    unless elements.empty?
      num_merchant_reviews_lifetime = elements.first.inner_text.strip
      merchant_source.num_merchant_reviews_lifetime = num_merchant_reviews_lifetime
    end

    merchant_source
  end

  def self.convert_search_results_page_to_merchant_array(search_results_doc, limit)
    result = []
    merchant_links = search_results_doc.search('tr[/td/font/a/font/b[text() = "Store Name"]]../tr/td/a')
    merchant_links.each_with_index do |merchant_link, index|
      break if index > limit-1
      merchant_link.attributes['href'].match(/^.*\/store\/(.+)$/)
      result << { :merchant_page_url => merchant_link.attributes['href'],
                  :merchant_code => $1,
                  :merchant_name => merchant_link.inner_text.strip }
    end
    result
  end

  def self.open_doc(url)
    response = ExternalUrl.fetch_response(url)
    if response[:success]
      doc = Hpricot(response[:response].body)
      final_uri = response[:final_uri]
      return {:doc => doc, :final_uri => final_uri}
    else
      return nil
    end
  end
end
