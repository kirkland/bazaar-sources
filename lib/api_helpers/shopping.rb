require File.join(File.dirname(__FILE__), 'api_helper')
require 'rubygems'
gem 'httparty', '>= 0.5.0'
require 'httparty'
require File.join(File.dirname(__FILE__), 'httparty_nokogiri_parser')

module Shopping
  class Error < StandardError
    attr_reader :code
    def initialize(message, code)
      super(message)
      @code = code
    end
  end

  class Publisher
    include ApiHelper
    include HTTParty
    parser HttpartyNokogiriParser
    format :xml
    base_uri 'http://publisher.api.shopping.com/publisher/3.0/rest/'
    default_params 'trackingId' => '3068547', 'apiKey' => SHOPPING_API_KEY

    MAX_OFFERS = 20
    PUTS_API_URL = false

    def fetch_product(product_id, include_specs=false, include_offers=false)
      # Won't get psuedo-redirected to new product ID unless we request at least one offer (very strange)
      query = {'numItems' => include_offers ? MAX_OFFERS : 1, 'productId' => product_id.strip, 'showProductSpecs' => include_specs ? 'true' : 'false'}
      call_api('/GeneralSearch', {:query => query}) do |doc|
        product_node = doc.at('GeneralSearchResponse/categories/category/items/product')
        convert_product_node(product_node, include_offers)
      end
    end

    def fetch_offers(product_id)
      query = {'numItems' => MAX_OFFERS, 'showOffersOnly' => 'true', 'productId' => product_id.strip}
      call_api('/GeneralSearch', {:query => query}) do |doc|
        items_node = doc.at('GeneralSearchResponse/categories/category/items')
        convert_offers_collection_node(items_node)
      end
    end

    def search_for_product(keyword, max_results=10)
      query = {'doSkipping' => 'false', 'showProductOffers' => 'false', 'numAttributes' => 0, 'numItems' => max_results, 'keyword' => keyword.strip}
      call_api('/GeneralSearch', {:query => query}) do |doc|
        product_nodes = doc.search('GeneralSearchResponse/categories/category/items/product')
        product_nodes.collect{|product_node| convert_product_node(product_node)}
      end
    end

    protected

    def call_api(path, options, &block)
      if PUTS_API_URL
        merged_options = self.class.default_options.dup.merge(options)
        puts "Shopping.com API URL: #{HTTParty::Request.new(Net::HTTP::Get, path, merged_options).uri}"
      end
      doc = self.class.get(path, options)
      errors = get_errors(doc)
      if errors.empty?
        yield doc
      else
        raise_exception(errors)
      end
    end

    def get_errors(doc)
      errors = []
      doc.search('GenericResponse/exceptions/exception') do |exception_node|
        message = exception_mode.at('message').text
        code = exception_node.at('code').text.to_i
        errors << Shopping::Error.new(message, code)
      end
      errors
    end

    def raise_exception(errors)
      raise errors.first
    end

    def convert_product_node(product_node, include_offers=false)
      product = {}
      product[:product_id] = product_node['id']
      product[:name] = product_node.at('name').text

      description = product_node.at('fullDescription').text
      if description.nil? || description.empty?
        description = product_node.at('shortDescription').text
      end
      product[:description] = (description.nil? || description.empty?) ? '' : description

      image_nodes = product_node.search('images/image[@available="true"]')
      images = image_nodes.collect{|x|
        {
          :width => x['width'].to_i,
          :height => x['height'].to_i,
          :url => x.at('sourceURL').text
        }
      }.sort_by{|x| x[:width] * x[:height] }

      product[:images] = {
        :small_image => images[0],
        :medium_image => images[1],
        :large_image => images[2]
      }

      # possible_manufacturers = (product / 'offer > manufacturer').collect{|x| x.text}.compact.uniq
      #
      # if possible_manufacturers.length == 1
      #   product[:manufacturer] = possible_manufacturers.first # easy peasy lemon squezy
      # elsif possible_manufacturers.length > 1
      #   # figure out which manufacturer is the most popular
      #   manufacturers_popularity_index = possible_manufacturers.inject({}) {|ha, manufacturer| ha[manufacturer] ||= 0; ha[manufacturer] += 1; ha }
      #   product[:manufacturer] = manufacturers_popularity_index.sort_by{|key, val| val }.last.first
      # else
      #   product[:manufacturer] = nil # zip, zero, doodad :(
      # end

      # rating
      review_count_node = product_node.at('rating/reviewCount')
      product[:num_reviews] = review_count_node.nil? ? 0 : review_count_node.text.to_i
      rating_value_node = product_node.at('rating/rating')
      product[:rating] = rating_value_node.nil? ? nil : normalize_product_rating(rating_value_node.text.to_f)

      # offers
      if include_offers
        offers_node = product_node.at('offers')
        product[:offers] = convert_offers_collection_node(offers_node) unless offers_node.nil?
      end

      # specifications
      specifications_node = product_node.at('specifications')
      product[:specifications] = convert_specifications_node(specifications_node) unless specifications_node.nil?

      product
    end

    def convert_offers_collection_node(offers_collection_node)
      offer_nodes = offers_collection_node.nil? ? nil : offers_collection_node.search('offer')
      return [] if offer_nodes.nil?
      offers = {}
      offer_nodes.each_with_index do |offer, offer_index|
        # in-stock
        stock_status = offer.at('stockStatus').text
        in_stock = stock_status != 'out-of-stock' && stock_status != 'back-order'

        if in_stock
          store = offer.at('store')
          store_hash = {
            :id => store['id'],
            :name => store.at('name').text,
            :trusted => store['trusted'] == "true",
            :authorized_reseller => store['authorizedReseller'] == 'true'
          }
          store_logo = store.at('logo')
          if store_logo['available'] == 'true'
            store_hash[:logo] = {
              :width => store_logo['width'],
              :height => store_logo['height'],
              :url => store_logo.at('sourceURL').text
            }
          else
            store_hash[:logo] = nil
          end

          # store rating
          store_rating = store.at('ratingInfo')
          store_hash[:rating] = {
            :number => store_rating.at('rating').nil? ? nil : normalize_merchant_rating(store_rating.at('rating').text.to_f),
            :count => store_rating.at('reviewCount').text.to_i,
            :url =>  store_rating.at('reviewURL').nil? ? nil : store_rating.at('reviewURL').text
          }

          # prices
          cpc = offer.at('cpc').nil? ? nil : (offer.at('cpc').text.to_f*100).to_i
          base_price = to_d_or_nil(offer.at('basePrice').text)
          shipping_cost = offer.at('shippingCost')['checkSite'] == 'true' ? nil : to_d_or_nil(offer.at('shippingCost').text)

          # skip this offer if we already have one from same merchant and it has a lower total price
          existing_offer = offers[store_hash[:id]]
          unless existing_offer.nil?
            next if existing_offer[:price] + (existing_offer[:shipping] || 0.0) < base_price + (shipping_cost || 0.0)
          end

          offers[store_hash[:id]] = { :original_index => offer_index,
                                      :merchant_code => store_hash[:id],
                                      :merchant_name => store_hash[:name],
                                      :merchant_logo_url => store_hash[:logo].nil? ? nil : store_hash[:logo][:url],
                                      :cpc => cpc,
                                      :price => base_price,
                                      :shipping => shipping_cost,
                                      :offer_url => offer.at('offerURL').text,
                                      :offer_tier => 1,
                                      :merchant_rating => store_hash[:rating][:number],
                                      :num_merchant_reviews => store_hash[:rating][:count] }
        end
      end
      offers.values.sort_by{|x| x[:price] + (x[:shipping] || 0) }
    end

    def convert_specifications_node(specifications_node)
      specifications = {}
      specifications_node.search('feature').each do |feature_node|
        feature_name = feature_node.at('name').text
        value_nodes = feature_node.search('value')
        if value_nodes.length > 1
          specifications[feature_name] = value_nodes.collect{|value_node| value_node.text}
        elsif value_nodes.length == 1
          specifications[feature_name] = value_nodes.first.text
        end
      end
      specifications
    end

    def normalize_product_rating(product_rating)
      product_rating.nil? ? nil : (product_rating * 20.0).round
    end

    def normalize_merchant_rating(merchant_rating)
      merchant_rating.nil? ? nil : (merchant_rating * 20.0).round
    end
  end
end
