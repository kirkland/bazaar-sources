require 'set'

class Source
  attr_reader :name
  attr_reader :homepage
  attr_reader :cpc
  attr_reader :offer_enabled
  alias :offer_enabled? :offer_enabled 
  attr_reader :offer_ttl_seconds
  attr_reader :use_for_merchant_ratings
  alias :use_for_merchant_ratings? :use_for_merchant_ratings
  attr_reader :offer_affiliate
  alias :offer_affiliate? :offer_affiliate
  attr_reader :supports_lifetime_ratings
  alias :supports_lifetime_ratings? :supports_lifetime_ratings
  attr_reader :batch_fetch_delay

  @@subclasses = []
  @@sources = Set.new
  @@sources_map = {}
  @@offer_sources = []
  @@affiliate_sources = []
  @@merchant_rating_sources = []

  class << self
    @keyname = nil
  end

  def self.keyname
    @keyname ||= self.name.match(/(.+)Source/)[1]
  end

  def self.inherited(child)
    @@subclasses << child
    set_source_keyname_const(child.keyname)
    super
  end

  def initialize(attributes)
    attributes.each {|k, v| instance_variable_set("@#{k}", v)}
  end

  def keyname
    self.class.keyname
  end

  def self.source(source_keyname)
    load_sources
    @@sources_map[source_keyname]
  end

  def self.sources
    load_sources
    @@sources
  end

  def self.offer_sources
    load_sources
    if @@offer_sources.empty?
      @@offer_sources = @@sources.select{|source| source.offer_enabled?}
    end
    @@offer_sources
  end

  def self.affiliate_sources
    load_sources
    if @@affiliate_sources.empty?
      @@affiliate_sources = @@sources.select{|source| source.offer_affiliate?}
    end
    @@affiliate_sources
  end

  def self.merchant_rating_sources
    load_sources
    if @@merchant_rating_sources.empty?
      @@merchant_rating_sources = @@sources.select{|source| source.use_for_merchant_ratings?}
    end
    @@merchant_rating_sources
  end

  def self.method_missing(meth)
    source = nil
    if matches = meth.to_s.match(/(.+)_source$/)
      source_keyname = matches[1].gsub(/(?:^|_)(.)/) { $1.upcase }
      source = send(:source, source_keyname)
    end
    source.nil? ? super : source
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

  def nullify_offer_url(offer_url)
    offer_url
  end

  def fetch_offers(product_source_codes)
    nil
  end

  def hash
    self.class.hash
  end

  def eql?(other)
    self.class == other.class
  end

  def to_s
    keyname
  end

  protected

  def self.set_source_keyname_const(source_keyname)
    unless source_keyname.nil? || source_keyname.empty?
      const_name = source_keyname.gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').gsub(/([a-z\d])([A-Z])/,'\1_\2').tr('-', '_').upcase + '_KEYNAME'
      const_set(const_name.to_sym, source_keyname)
    end
  end

  def self.load_sources
    if @@sources.empty?
      @@subclasses.each do |source_class|
        source_instance = source_class.new
        @@sources << source_instance
        @@sources_map[source_instance.keyname] = source_instance
      end
      @@sources.sort{|a,b| a.name <=> b.name}
    end
    nil
  end

  def delay_fetch
    if !@last_fetched_at.nil? &&
       batch_fetch_delay > 0 &&
       @last_fetched_at > batch_fetch_delay.seconds.ago
      sleep(batch_fetch_delay)
    end
    @last_fetched_at = Time.now
  end
end
