require 'ostruct'

class PriceGrabberSource < Source
  def initialize
    super(:name => 'PriceGrabber',
          :homepage => ' http://www.pricegrabber.com/',
          :cpc => 0,
          :offer_enabled => false,
          :offer_ttl_seconds => 0,
          :use_for_merchant_ratings => true,
          :offer_affiliate => false,
          :supports_lifetime_ratings => false,
          :batch_fetch_delay => 2,
          :product_code_regexp => /^\d{6,9}$/,
          :product_code_examples => ['716698181', '563043'],
          :product_page_link_erb => "http://reviews.pricegrabber.com/-/m/<%= product_code %>/")
  end
  
  def url_for_merchant_source_page(merchant_source_code)
    "http://www.pricegrabber.com/info_retailer.php/r=#{merchant_source_code}"
  end

  def code_from_merchant_source_page_url(merchant_source_page_url)
    merchant_source_page_url.match(/pricegrabber\.com.*\/r[\/=](\d+)/)[1]
  end

  def fetch_merchant_source(merchant_source_page_url)
    delay_fetch
    doc = Hpricot(open(merchant_source_page_url))

    merchant_source = OpenStruct.new
    merchant_source.source = self

    merchant_identity_block = doc.at('div#merchantIdentityBlock')

    unless merchant_identity_block.nil?
      # merchant name
      element = merchant_identity_block.at('/h4')
      unless element.nil?
        name = element.inner_text.strip
        merchant_source.name = name
      end

      # merchant logo
      element = merchant_identity_block.at('/img')
      unless element.nil?
        logo_url = element.attributes['src']
        merchant_source.logo_url = logo_url
      end
    end

    # merchant code
    merchant_source.code = code_from_merchant_source_page_url(merchant_source_page_url)

    # merchant rating
    ratings = doc.search('table#scoreTable/tr/th[text() = "Avg Rating"]/../td')
    unless ratings.nil?
      unless ratings[0].nil?
        three_month_rating = ratings[0].inner_text.strip.to_f
        merchant_source.merchant_rating = (three_month_rating * 20).round
      end

      unless ratings[2].nil?
        lifetime_month_rating = ratings[2].inner_text.strip.to_f
        merchant_source.merchant_rating_lifetime = (lifetime_month_rating * 20).round
      end
    end

    # Num Merchant Reviews
    num_reviews = doc.search('table#scoreTable/tr/th[text() = "Total Reviews"]/../td')
    unless num_reviews.nil?
      unless num_reviews[0].nil?
        merchant_source.num_merchant_reviews = num_reviews[0].inner_text.strip.to_i
      end

      unless num_reviews[2].nil?
        merchant_source.num_merchant_reviews_lifetime = num_reviews[2].inner_text.strip.to_i
      end
    end

    # Homepage
    element = doc.at('table#contactTable//th[text() = "Website:"]/../td/a')
    unless element.nil?
      homepage = element.inner_text.strip.downcase
      merchant_source.homepage = homepage
    end

    merchant_source
  end

  def format_rating(merchant_source)
    '%01.2f/5.0' % (merchant_source.get_merchant_rating.to_f / 20.0)
  end
end
