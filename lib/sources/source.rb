# == Schema Information
# Schema version: 20090929200939
#
# Table name: sources
#
#  id                       :integer         not null, primary key
#  type                     :string(128)
#  keyname                  :string(32)      not null
#  name                     :string(64)      not null
#  homepage                 :string(256)
#  batch_fetch_delay        :integer         default(0), not null
#  cpc                      :integer         default(0), not null
#  created_at               :datetime
#  updated_at               :datetime
#  offer_ttl_seconds        :integer         default(0), not null
#  offer_enabled            :boolean         not null
#  use_for_merchant_ratings :boolean         not null
#  offer_affiliate          :boolean         not null
#

class Source
  AMAZON_KEYNAME = 'AMAZON'
  BUY_KEYNAME = 'BUY'
  EBAY_KEYNAME = 'EBAY'
  EPINIONS_KEYNAME = 'EPINIONS'
  GOOGLE_KEYNAME = 'GOOGLE'
  PRICE_GRABBER_KEYNAME = 'PRICE_GRABBER'
  RESELLER_RATINGS_KEYNAME = 'RESELLER_RATINGS'
  SHOP_CART_USA_KEYNAME = 'SHOP_CART_USA'
  SHOPPING_KEYNAME = 'SHOPPING'
  SHOPZILLA_KEYNAME = 'SHOPZILLA'

  attr_reader :name
  attr_reader :keyname
  attr_reader :homepage
  attr_reader :cpc
  attr_reader :offer_enabled
  attr_reader :offer_ttl_seconds
  attr_reader :use_for_merchant_ratings
  attr_reader :offer_affiliate
  attr_reader :batch_fetch_delay

  def initialize(attributes)
    attributes.each {|k, v| instance_variable_set("@#{k}", v)}
  end

  def self.source(source_keyname)
    get_cache(source_keyname) { find_by_keyname(source_keyname) }
  end

  def self.sources
    get_cache(:all) { find(:all, :order => 'cpc DESC, name ASC') }
  end

  def self.offer_sources
    get_cache(:offer_sources) { find(:all, :conditions => {:offer_enabled => true}, :order => 'cpc DESC, name ASC') }
  end

  def self.offer_affiliates
    get_cache(:offer_affiliates) { find(:all, :conditions => {:offer_affiliate => true}, :order => 'cpc DESC, name ASC') }
  end

  def self.merchant_rating_sources
    get_cache(:merchant_rating_sources) { find(:all, :conditions => {:use_for_merchant_ratings => true}, :order => 'name ASC') }
  end

  def self.amazon_source
    source(AMAZON_KEYNAME)
  end

  def self.shopping_source
    source(SHOPPING_KEYNAME)
  end

  def self.reseller_ratings_source
    source(RESELLER_RATINGS_KEYNAME)
  end

  def self.shopzilla_source
    source(SHOPZILLA_KEYNAME)
  end

  def self.shop_cart_usa_source
    source(SHOP_CART_USA_KEYNAME)
  end

  def self.price_grabber_source
    source(PRICE_GRABBER_KEYNAME)
  end

  def to_s
    keyname
  end

  def supports_lifetime_ratings
    false
  end

  def url_for_merchant_source_page(merchant_source_code)
    nil
  end

  def url_for_merchant_source_page_alt(merchant_source_alt_code)
    nil
  end

  def code_from_merchant_source_page_url(merchant_source_page_url)
    nil
  end

  def fetch_merchant_source(merchant_source_page_url)
    nil
  end

  def format_rating(merchant_source)
    "#{merchant_source.get_merchant_rating}%"
  end

  def source_product_id(product)
    nil
  end

  def deal_offer_transparent?(deal_offer)
    true
  end

  def nullify_offer_url(offer_url)
    offer_url
  end

  def fetch_product_offers(product)
    nil
  end
  
  protected

  def delay_fetch
    if !@last_fetched_at.nil? &&
       batch_fetch_delay > 0 &&
       @last_fetched_at > batch_fetch_delay.seconds.ago
      sleep(batch_fetch_delay)
    end
    @last_fetched_at = Time.now
  end
end
