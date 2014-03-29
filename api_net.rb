module API
  module Internety
    mattr_accessor :m_engine #= :curl, :typhoeus, :httparty,, :http

    def self.init(engine)
      @@m_engine = engine
      case engine
        when :curl
          require 'curb'
        when :typhoeus
          require 'typhoeus'
        when :httparty
          require 'httparty'
        when :http
          require 'net/http'
          require 'net/https'
        else
          Globals.error(:design, '89234813844')
      end
    end

    def self.http(uri, hardTimeout)
      verb = uri[:verb]
      engine = @@m_engine
      case engine
        when :curl
          return http_curl(verb, uri, hardTimeout)
        when :typhoeus
          return http_typhoeus(verb, uri, hardTimeout)
        when :httparty
          return http_httparty(verb, uri, hardTimeout)
        when :http
          return http_http(verb, uri, hardTimeout)
        else
          Globals.error(:design, '89234813844')
      end
    end

    def self.http_curl(verb, uri, hardTimeout)
      #https://www.bitstamp.net/api/ticker
      start_total_time = Time.now
      c = Curl::Easy.new(uri[:URI].scheme + '://' + uri[:URI].host + uri[:URI].request_uri)
      c.timeout = hardTimeout # == 2[s]
      paramsQue = uri[:options].collect {|k,v| "#{k}=#{v}"}.join('&')
      c.post_body = paramsQue
      c.headers.merge!(uri[:headers]) if uri[:headers] != {}

      begin
        c.http(verb.to_s)

        http_time = c.total_time
        resp = c.body_str
        ctype = c.content_type
        respLength = resp.length
        total_time = Time.now - start_total_time

        return {:data => resp, :ctype => ctype, :http_time => http_time, :total_time => total_time}
      end
    end

    def self.http_http(verb, uri, hardTimeout)
      start_total_time = Time.now

      http = Net::HTTP.new uri[:URI].host, uri[:URI].port
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      if verb == :GET
        request = Net::HTTP::Get.new uri[:URI].request_uri
      else
        # If sending params, then we want a post request for authentication.
        request = Net::HTTP::Post.new uri[:URI].request_uri
        if uri[:headers] != {}
          request.add_field "Key", uri[:headers]["Key"] if uri[:headers].has_key?("Key")
          request.add_field "Sign", uri[:headers]["Sign"] if uri[:headers].has_key?("Sign")
        end

        request.set_form_data uri[:options]
      end
      start_http_time = Time.now
      response = http.request request
      http_time = Time.now - start_http_time

      resp = response.body
      total_time = Time.now - start_total_time

      return {:data => resp, :ctype => '', :http_time => http_time, :total_time => total_time}
    end

    def self.http_httparty(verb, uri, hardTimeout)
      start_total_time = Time.now

      #HTTParty.default_timeout(hardTimeout)
      start_http_time = Time.now
      if verb == :GET
        response = HTTParty.get(uri[:URI].scheme + '://' + uri[:URI].host + uri[:URI].request_uri)
      else
        post_data = uri[:options]
        headers = uri[:headers].merge({"User-Agent" => "Mozilla/4.0 (compatible; API ruby client)"})

        start_http_time = Time.now
        response = HTTParty.post(
            uri[:URI].scheme + '://' + uri[:URI].host + uri[:URI].request_uri,
            headers: headers,
            body: post_data
        )
      end
      http_time = Time.now - start_http_time

      resp = response.body
      total_time = Time.now - start_total_time

      return {:data => resp, :ctype => '', :http_time => http_time, :total_time => total_time}
    end

    def self.http_typhoeus(verb, uri, hardTimeout)
      start_total_time = Time.now

      if verb == :GET
        request = Typhoeus::Request.new(uri[:URI].scheme + '://' + uri[:URI].host + uri[:URI].request_uri)
        #request.timeout = hardTimeout
        hydra = Typhoeus::Hydra.hydra
        hydra.queue(request)
        hydra.run
        response = request.response

        resp = response.body
        http_time = response.total_time
        total_time = Time.now - start_total_time

        return {:data => resp, :ctype => '', :http_time => http_time, :total_time => total_time}

      else
        request = Typhoeus::Request.new(
            uri[:URI].scheme + '://' + uri[:URI].host + uri[:URI].request_uri,
            method: :post,
            body: uri[:options],
            headers: uri[:headers]
        )
        #request.timeout = hardTimeout

        hydra = Typhoeus::Hydra.hydra
        hydra.queue(request)
        hydra.run
        response = request.response

        resp = response.body
        http_time = response.total_time
        total_time = Time.now - start_total_time

        return {:data => resp, :ctype => '', :http_time => http_time, :total_time => total_time}
      end
    end
  end
end