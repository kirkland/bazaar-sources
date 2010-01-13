require 'ostruct'
require 'api_helpers/shopping'

class ShoppingSource < Source
  def initialize
    super(:name => 'Shopping.com',
          :homepage => 'http://www.shopping.com/',
          :cpc => 50,
          :offer_enabled => true,
          :offer_ttl_seconds => 1800,
          :use_for_merchant_ratings => true,
          :offer_affiliate => false,
          :supports_lifetime_ratings => false,
          :batch_fetch_delay => 2)
  end

  def api
    @api = Shopping::Publisher.new
  end

  def url_for_merchant_source_page(merchant_source_code)
    "http://www.shopping.com/xMR-~MRD-#{merchant_source_code}"
  end

  def fetch_merchant_source(merchant_source_page_url)
    delay_fetch
    doc = nil
    4.times do |i|
      # This is a workaround for some weirdness with Shopping.com.
      # About one in ten requests for a merchant's info page results
      # in a page with zeros for everything (as if the merchant has
      # never been reviewed).  One indication that we received the
      # bogus page is the the title will look like:
      # Shopping.com: null - Compare Prices &amp; Read Reviews
      # If we see that 'null' in the title, try fetching the page
      # again (up to 4 times).
      doc = Hpricot(open(merchant_source_page_url))
      page_title = doc.at('head/title').inner_text
      break if page_title.match(/ null /).nil?
    end

    merchant_source = OpenStruct.new
    merchant_source.source = self

    # merchant name
    element = doc.at('h1[@class = "pageTitle"]')
    unless element.nil?
      name = element.inner_text.strip
      merchant_source.name = name
    end

    # merchant logo
    element = doc.at('img[@class = "logoBorder1"]')
    unless element.nil?
      logo_url = element.attributes['src']
      merchant_source.logo_url = logo_url

      # merchant code
      code = logo_url.match(/merch_logos\/(.+)\.gif/)[1]
      merchant_source.code = code
    end

    # merchant rating
    element = doc.at('td[@id = "image"]/img')
    unless element.nil?
      merchant_rating = element.attributes['title'].match(/((\d|,)*\.?\d)/)[1]
      merchant_source.merchant_rating = merchant_rating.delete(',').to_f * 20.0 unless merchant_rating.nil?
    end

    # Num Merchant Reviews
    element = doc.at('table[@class = "boxTableTop"]//h3[@class = "boxTitleNB"]')
    unless element.nil?
      num_merchant_reviews = element.inner_text.match(/of\s+((\d|,)+)/)[1]
      merchant_source.num_merchant_reviews = num_merchant_reviews.delete(',').to_i unless num_merchant_reviews.nil?|| num_merchant_reviews.empty?
    end

    merchant_source
  end

  def search_for_merchant_source(search_text)
    merchant_search_url = "http://www.shopping.com/xSD-#{CGI::escape(search_text.strip)}"
    doc = Hpricot(open(merchant_search_url))
    merchant_sources = []
    element = doc.search('div[@class*="contentContainer"]/div[@class="boxMid"]')[1]

    # Do we have any results?
    unless element.nil?
      element.search('tr[td/div/ul/li/a/span[text() = "See Store Info"]]').each do |result_row|
        element = result_row.at('/td/a')
        name = element.inner_text.strip
        merchant_code = element.attributes['href'].match(/~MRD-(\d+)/)[1]
        element = result_row.at('/td[@class = "smallTxt"]/img')
        logo_url = element.attributes['src'] unless element.nil?

        existing_merchant_source = MerchantSource.find_by_source_and_code(self, merchant_code)
        if existing_merchant_source.nil?
          merchant_sources << OpenStruct.new({:source => self, :name => name, :code => merchant_code, :logo_url => logo_url})
        else
          merchant_sources << existing_merchant_source
        end
      end
    end
    merchant_sources
  end

  def format_rating(merchant_source)
    '%01.1f/5.0' % (merchant_source.get_merchant_rating.to_f / 20.0)
  end

  def nullify_offer_url(offer_url)
    offer_url.gsub(/3068547/, '8039098')
  end

  def fetch_street_price(product_source_codes)
    delay_fetch
    offers = fetch_offers(product_source_codes)
    num_offers = 0
    total_prices = 0.0
    offers.each do |offer|
      if !offer.merchant_rating.nil? &&
         offer.merchant_rating >= 55 &&
         !offer.price.nil? &&
         !offer.shipping.nil?
        total_prices += offer.total_price
        num_offers += 1
      end
    end
    num_offers.zero? ? nil : (total_prices / num_offers)
  end

  def fetch_offers(product_code)
    api.fetch_offers(product_code)
  end
end
