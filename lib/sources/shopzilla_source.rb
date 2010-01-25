require 'ostruct'
require 'api_helpers/shopzilla_api'

class ShopzillaSource < Source
  def initialize
    super(:name => 'Shopzilla',
          :homepage => 'http://www.shopzilla.com/',
          :cpc => 39,
          :offer_enabled => false,
          :offer_ttl_seconds => 1800,
          :use_for_merchant_ratings => true,
          :offer_affiliate => false,
          :supports_lifetime_ratings => false,
          :batch_fetch_delay => 1,
          :product_code_regexp => /^\d{7,11}$/,
          :product_code_examples => ['1028968032', '852926140'],
          :product_page_link_erb => "http://www.shopzilla.com/-/<%= product_code %>/shop")
  end
  
  def url_for_merchant_source_page(merchant_source_code)
    "http://www.shopzilla.com/6E_-_mid--#{merchant_source_code}"
  end

  def code_from_merchant_source_page_url(merchant_source_page_url)
    merchant_source_page_url.match /6[A-Z](\-\-.*)?_\-_mid\-\-(\d+)/i
    $2
  end

  def fetch_merchant_source(merchant_source_page_url)
    delay_fetch
    merchant_source = OpenStruct.new
    merchant_source.source = self

    merchant_code = code_from_merchant_source_page_url(merchant_source_page_url)
    merchant_source_detail = api.merchant_source_detail(merchant_code)

    unless merchant_source_detail.nil?
      merchant_source.code = merchant_source_detail[:code]
      merchant_source.name = merchant_source_detail[:name]
      merchant_source.logo_url = merchant_source_detail[:logo_url]
      merchant_source.merchant_rating = merchant_source_detail[:merchant_rating]
      merchant_source.homepage = merchant_source_detail[:homepage]
      merchant_source.num_merchant_reviews = merchant_source_detail[:num_merchant_reviews]
    end
    merchant_source
  end

  SHOPZILLA_SEARCH_PAGE = 'http://www.bizrate.com/ratings_guide/guide.html'
  SHOPZILLA_SEARCH_ACTION = 'http://www.bizrate.com/merchant/results.xpml'
  def search_for_merchant_source(search_text)
    merchant_sources = []

    agent = WWW::Mechanize.new
    agent.html_parser = Nokogiri::HTML
    agent.user_agent_alias = 'Windows IE 7'
    agent.follow_meta_refresh = true

    search_page = agent.get(SHOPZILLA_SEARCH_PAGE)
    if form = search_page.form_with(:action => /superfind/)
      # Must switch the action given in the form, because BizRate does exactly this in JavaScript
      form.action = SHOPZILLA_SEARCH_ACTION
      form['SEARCH_GO'] = 'Find it!'
      form.keyword = search_text
      if result = form.submit
        if single_store = result.at('table[id="merchant_overview"]')
          if store = single_store.at('div[class="certified"] strong a')
            add_merchant_source_from_store(merchant_sources, store)
          end
        elsif stores_rated_list = result.at('div[class="storesRatedList"]')
          if stores = stores_rated_list.search('th a')
            stores.each do |store|
              add_merchant_source_from_store(merchant_sources, store)
            end
          end
        end
      end
    end
    merchant_sources
  end
  
  def add_merchant_source_from_store(merchant_sources, store)
    name = store.text
    merchant_code = CGI.parse(URI.parse(store['href']).query)['mid']
    logo_url = api.verified_logo_url(merchant_code)
    existing_merchant_source = MerchantSource.find_by_source_and_code(self, merchant_code)
    if existing_merchant_source.nil?
      merchant_sources << OpenStruct.new({:source => self, :name => name, :code => merchant_code, :logo_url => logo_url})
    else
      merchant_sources << existing_merchant_source
    end
  end
  
  def format_rating(merchant_source)
    '%01.1f/10' % (merchant_source.get_merchant_rating.to_f / 10.0)
  end

  def nullify_offer_url(offer_url)
    offer_url.gsub(/af_id=3973/, 'af_id=3233')
  end

  def api
    @api ||= ShopzillaAPI.new
  end

  def fetch_offers(product_source_codes)
    unless product_source_codes.empty?
      api.find_offers_by_product_id(product_source_codes.first)
    else
      []
    end
  end
end
