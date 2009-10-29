module ExternalUrl
  require 'net/http'
  require 'uri'

  REQUEST_HEADERS = {
    'User-Agent' => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.11) Gecko/20071127 Firefox/2.0.0.11'
  }

  # Note: This method is only used now by the Validator, and is only suitable for the Validator.
  def self.just_page_content(page)
    # No longer used
    justbody = /.*?<body.*?>(.*)<\/body>/im
    comments = /(<!--.*?-->)(.{1,40})/m
    nostyle = /<style.*?<\/style>/im
    notags = /<.*?>/im
    noentities = /&.*?;/
    noextrawhitespace = /(\s)+/im
    # Remove comments, unless inside of JavaScript (because frequently JavaScript has good matches for model numbers, etc.)
    page.gsub(comments) do |c|
      comment = $1
      post = $2
      if post =~ /<\/script/
        comment + post
      else
        post
      end
    end.gsub(nostyle,' ').gsub(notags,'').gsub(noentities,' ').gsub(noextrawhitespace,'\1')
  end

  # returns a hash containing :success flag; if true, you'll have the :response (thus response.body) and :final_uri
  # (e.g. if redirected) If false a :message is set and :final_uri
  def self.fetch_response(url, limit = 10, debug = false)
    begin
      if limit == 0
        return {:success => false, :response => nil, :message => "Redirected too many times", :final_uri => url}
      end

      message = self.invalid_uri(url)
      if message
        return {:success => false, :response => nil, :message => message, :final_uri => url}
      end
      uri = URI.safe_parse(url.to_s)
      http_request = Net::HTTP.new(uri.host)
      if debug
        puts "http request: #{http_request.inspect}"
      end
      # Adding user agent header helps some merchants feel more comfortable with our bot
      no_host_url = uri.to_s.gsub(/.*?#{uri.host}(.*)/,'\1')
      if debug
        puts "http request to: #{no_host_url}"
      end
      response = http_request.get(no_host_url, REQUEST_HEADERS)
      if debug
        puts "http response: #{response.inspect}"
      end

      case response
      when Net::HTTPSuccess then
        if debug
          puts "Success, final url: #{url}"
          ExternalUrl.to_file(url, response.body, "html")
          ExternalUrl.to_file(url, ExternalUrl.just_page_content(response.body), "txt")
        end
        {:success => true, :response => response, :final_uri => url}
      when Net::HTTPRedirection then
        redirect_url = to_absolute_url(response['location'], url)
        if debug
          puts "Redirecting to #{redirect_url}"
        end
        self.fetch_response(redirect_url, limit - 1, debug)
      else
        {:success => false, :response => response, :final_uri => url}
      end
    rescue Exception => exp
      {:success => false, :response => nil, :message => exp.message, :final_uri => url}
    end
  end

  private

  def self.to_file(url, content, ext = "html")
    uri = URI.safe_parse(url.to_s)
    filename_base = "#{uri.host}.#{uri.path}?#{uri.query}"
    filename = filename_base.gsub(/(\W)+/,"-") + ".#{ext}"
    f = File.new(filename, "w")
    f.write(content)
    f.close
    puts "Wrote content to file #{filename} in #{Dir.pwd}"
  end

  # Returns nil if the URL is a valid URI, else a message.  In this case, scheme, host and path are all required.
  def self.invalid_uri(url)
    return 'No URL' if url.nil? || url.empty?
    begin
      uri = URI.safe_parse(url)
      if uri.nil? || uri.scheme.nil? || uri.host.nil? || uri.path.nil?
        if uri.nil?
          return "URL is not well formed"
        else
          return "URL incomplete: scheme is #{uri.scheme.nil? ? "missing" : uri.scheme}, host is #{uri.host.nil? ? "missing" : uri.host} and path is #{uri.path.nil? ? "missing" : uri.path}"
        end
      end
    rescue Exception => exp
      return "URI improperly formed: #{exp.message}"
    end
    return nil
  end

  def self.to_absolute_url(url, current_url)
    unless url.is_a? URI
      url = URI.safe_parse(url)
    end

    # construct an absolute url
    if url.relative?
      unless current_url.is_a? URI
        current_url = URI.safe_parse(current_url)
      end

      url.scheme = current_url.scheme
      url.host = current_url.host
      url.port = current_url.port unless current_url.port == 80
    end

    return url.to_s
  end
end
