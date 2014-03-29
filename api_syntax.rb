#all market specific code here

module API
  module Syntax
    mattr_accessor :m_marketData
    mattr_accessor :m_exchange
    mattr_accessor :m_apiModel
    mattr_accessor :m_apiCred

    def self.init(apiModel)
      @@m_marketData, @m_exchange, coinMaster, coinSlave = Market.get_market
      @@m_apiModel = apiModel
      @@m_apiCred = Market.m_apiCred
      #TODO init syntax submodule - nonces and shit
    end

    def self.getNonce()
      case @@m_marketData[:exchange]
        when :btce
          sleep(1)
          return Time.now.to_i.to_s
          nowF = Time.now.to_f
          nowFad = nowF - 1391099524
          return (nowFad*100).to_i.to_s

        when :cryptsy
          return (Time.now.to_f*1000).to_i.to_s

        when :bitstamp
          return (Time.now.to_f*1000).to_i.to_s

        else
          return Time.now.to_i.to_s
      end
    end

    def self.get_market_data()
      return @@m_marketData
    end

    def self.getNoncePar()
    end
    def self.sign()
    end
    def self.getQueryLimit()
      return @@m_exchange[:trans_limit]
    end

    def self.getURI(command, optHash)
      nonce = 0
      nonce = getNonce() if @@m_apiModel == :dbSeq
      nonce = getNoncePar() if @@m_apiModel == :dbPar

      case @@m_marketData[:exchange]
        when :btce
          uri = {}
          uri[:URI] = URI.parse 'https://btc-e.com/tapi'

          params = {}
          params["nonce"] = nonce

          case command
            when 'balance'
              params["method"] = 'getInfo'
              uri[:verb] = :POST
            when 'ticker'
              uri[:URI] = URI.parse "https://btc-e.com/api/3/ticker/#{@@m_marketData[:pair]}"
              uri[:verb] = :GET
            when 'depth'
              uri[:URI] = URI.parse "https://btc-e.com/api/3/depth/#{@@m_marketData[:pair]}"
              uri[:verb] = :GET
            when 'user_tran'
              params["method"] = 'TradeHistory'
              params["from"] = optHash[:offset] if optHash.has_key?(:offset)
              params["count"] = optHash[:limit] if optHash.has_key?(:limit)
              params["order"] = optHash[:sort] if optHash.has_key?(:sort)
              params["pair"] = @@m_marketData[:pair]
              uri[:verb] = :POST
            when 'open_ord'
              params["method"] = 'ActiveOrders'
              params["pair"] = @@m_marketData[:pair]
              uri[:verb] = :POST
            when 'cancel_ord'
              params["method"] = 'CancelOrder'
              params["order_id"] = optHash[:oid]
              uri[:verb] = :POST
            when 'place_ord'
              params["method"] = 'Trade'
              params["amount"] = optHash[:amount]
              params["rate"] = optHash[:price]
              params["type"] = optHash[:price] == 0 ? 'buy' : 'sell'
              params["pair"] = @@m_marketData[:pair]
              uri[:verb] = :POST
          end

          if uri[:verb] == :POST
            uri[:options] = params

            hmac = OpenSSL::HMAC.new(@@m_apiCred[:btce][:secret], OpenSSL::Digest::SHA512.new)
            paramsQue = params.collect {|k,v| "#{k}=#{v}"}.join('&')
            signed = hmac.update paramsQue

            headers = {}
            headers["Key"] = @@m_apiCred[:btce][:key]
            headers["Sign"] = signed.to_s
            uri[:headers] = headers
          else
            uri[:headers] = {}
            uri[:options] = {}
          end

          return uri


        when :cryptsy
          uri = {}
          uri[:URI] = URI.parse 'https://www.cryptsy.com/api'

          params = {}
          params["nonce"] = nonce

          case command
            when 'balance'
              params["method"] = 'getinfo'
              uri[:verb] = :POST
            when 'ticker'
              uri[:URI] = URI.parse "http://pubapi.cryptsy.com/api.php?method=singlemarketdata&marketid=#{@@m_marketData[:marketid]} "
              uri[:verb] = :GET
            when 'depth'
              params["method"] = 'depth'
              params["marketid"] = @@m_marketData[:marketid]
              uri[:verb] = :POST
            when 'user_tran'
              params["method"] = 'mytrades'
              params["marketid"] = @@m_marketData[:marketid]
              params["limit"] = optHash[:limit] if optHash.has_key?(:limit)
              uri[:verb] = :POST
            when 'open_ord'
              params["method"] = 'myorders'
              params["marketid"] = @@m_marketData[:marketid]
              uri[:verb] = :POST
            when 'cancel_ord'
              params["method"] = 'cancelorder'
              params["orderid"] = optHash[:oid]
              uri[:verb] = :POST
            when 'place_ord'
              params["method"] = 'createorder'
              params["price"] = optHash[:price]
              params["quantity"] = optHash[:amount]
              params["marketid"] = @@m_marketData[:marketid]
              if optHash[:type] == 0
                params["ordertype"] = 'Buy'
              else
                params["ordertype"] = 'Sell'
              end
              uri[:verb] = :POST
          end

          if uri[:verb] == :POST
            uri[:options] = params

            hmac = OpenSSL::HMAC.new(@@m_apiCred[:cryptsy][:secret], OpenSSL::Digest::SHA512.new)
            paramsQue = params.collect {|k,v| "#{k}=#{v}"}.join('&')
            signed = hmac.update paramsQue

            headers = {}
            headers["Key"] = @@m_apiCred[:cryptsy][:key]
            headers["Sign"] = signed.to_s
            uri[:headers] = headers
          else
            uri[:headers] = {}
            uri[:options] = {}
          end

          return uri


        when :bitstamp
          uri = {}
          uri[:URI] = URI.parse 'https://www.bitstamp.net/api'

          params = {}
          params["key"] = @@m_apiCred[:bitstamp][:key]
          params["nonce"] = nonce
          params["signature"] = HMAC::SHA256.hexdigest(@@m_apiCred[:bitstamp][:secret], params["nonce"]+@@m_apiCred[:bitstamp][:client_id]+params["key"]).upcase

          case command
            when 'balance'
              uri[:URI] = URI.parse 'https://www.bitstamp.net/api/balance/'
              uri[:verb] = :POST
              uri[:bitstamp_command] = 'balance'
            when 'ticker'
              uri[:URI] = URI.parse 'https://www.bitstamp.net/api/ticker/'
              uri[:verb] = :GET
              uri[:bitstamp_command] = 'ticker'
            when 'depth'
              uri[:URI] = URI.parse 'https://www.bitstamp.net/api/order_book/'
              uri[:verb] = :GET
              uri[:bitstamp_command] = 'order_book'
            when 'user_tran'
              params["offset"] = optHash[:offset] if optHash.has_key?(:offset)
              params["limit"] = optHash[:limit] if optHash.has_key?(:limit)
              params["sort"] = optHash[:sort] if optHash.has_key?(:sort)
              uri[:URI] = URI.parse 'https://www.bitstamp.net/api/user_transactions/'
              uri[:verb] = :POST
              uri[:bitstamp_command] = 'user_transactions'
            when 'open_ord'
              uri[:URI] = URI.parse 'https://www.bitstamp.net/api/open_orders/'
              uri[:verb] = :POST
              uri[:bitstamp_command] = 'open_orders'
            when 'cancel_ord'
              params["id"] = optHash[:oid]
              uri[:URI] = URI.parse 'https://www.bitstamp.net/api/cancel_order/'
              uri[:verb] = :POST
              uri[:bitstamp_command] = 'cancel_order'
            when 'place_ord'
              params["price"] = optHash[:price]
              params["amount"] = optHash[:amount]
              if optHash[:type] == 0
                uri[:URI] = URI.parse 'https://www.bitstamp.net/api/buy/'
                uri[:bitstamp_command] = 'buy'
              else
                uri[:URI] = URI.parse 'https://www.bitstamp.net/api/sell/'
                uri[:bitstamp_command] = 'sell'
              end
              uri[:verb] = :POST
            else
              Globals.error(:design, "684672157")
          end

          if uri[:verb] == :POST
            uri[:options] = params
            headers = {}
            uri[:headers] = headers
          else
            uri[:headers] = {}
            uri[:options] = {}
          end

          return uri
        else
          Globals.error(:design, "6846721574")
      end

      uri = {:URI => 0, :header => {}, :options => {}}
    end

    def self.testResp(command, resp)
      #in one correct case bitstamp do not return correct JSON
      if @@m_marketData[:exchange] == :bitstamp && command == 'cancel_ord'
        return :success, true   if resp[:data] == 'true'
      end

      begin
        json = JSON.parse(resp[:data], :symbolize_names => true)
        return :success, json
      rescue StandardError => e
        return :unknown, nil
      end
    end

    def self.parse(command, optHash, resp, fireTurnTime)
      test, json = testResp(command, resp)
      if test != :success
        return {:status => test}
      end

      begin
        case @@m_marketData[:exchange]
          when :bitstamsp
            if json.class == Hash && json.has_key?(:error)
              error_resp = parseError(command, json[:error])
              return error_resp
            end
            case command
              when 'balance'
                data = {:availMaster => json[:usd_available], :availSlave => json[:btc_available], :time => fireTurnTime}
                data[:totalMaster] = json[:usd_balance]
                data[:totalSlave] = json[:btc_balance]
                return {:status => :success, :data => data}
              when 'ticker'
                data = {:last => json[:last], :ask => json[:ask], :bid => json[:bid], :high => json[:high], :low => json[:low], :volume => json[:volume], :time => fireTurnTime, :srvTime => json[:timestamp]}
                return {:status => :success, :data => data}
              when 'depth'
                data = {:ask => json[:asks], :bid => json[:bids], :time => fireTurnTime, :srvTime => json[:timestamp]}
                return {:status => :success, :data => data}
              when 'user_tran'
                #[{:tid => 0, :oid => 0, :master => 0, :slave => 0, :feeAmountMaster => 0, :feeAmountSlave => 0, :type => 0, :srvTime => 0}]
                user_tran = []
                json.each do |item|
                  if item[:type] == 2
                    trans = {:tid => item[:id], :oid => item[:order_id], :master => item[:usd].to_f.abs, :slave => item[:btc].to_f.abs, :feeAmountMaster => item[:fee], :feeAmountSlave => 0, :type => item[:btc].to_f>0 ? 0 : 1, :srvTime => Globals.time2unix(item[:datetime])}
                    user_tran << trans
                  end
                end
                data = {:user_tran => user_tran, :time => fireTurnTime}
                return {:status => :success, :data => data}
              when 'open_ord'
                #[{:oid => 0, :price => 0, :amountOrig => 0, :amountPending => 0, :type => 0, :srvTime => 0}]
                open_ord = []
                json.each do |item|
                  ord = {:oid => item[:id], :price => item[:price].to_f, :amountPending => item[:amount].to_f, :type => item[:type].to_i, :srvTime => Globals.time2unix(item[:datetime])}
                  open_ord << ord
                end
                open_ord.sort!{|x, y| x[:oid] <=> y[:oid]}
                data = {:open_ord => open_ord, :time => fireTurnTime}
                return {:status => :success, :data => data}
              when 'cancel_ord'
                if json == 'true'
                  return {:status => :success, :data => {}}
                end
              when 'place_ord'
                #{:oid => 0, :srvTime => 0, :error => :fail}
                #{:data=>"{\"price\": \"500\", \"amount\": \"0.01\", \"type\": 0, \"id\": 16435329, \"datetime\": \"2014-02-10 10:02:39.092192\"}", :ctype=>"", :time=>0.401017}
                data = {:oid => json[:id], :srvTime => Globals.time2unix(json[:datetime])}
                return {:status => :success, :data => data}
            end
            #if we got there our syntax model is incomplete
            Globals.error(:syntax, "580192365")

          else
            #if we got there we do not have processing branch for supplied exchange
            Globals.error(:design, "130981279")
            case command
              when 'balance'
                data = {:availMaster => 0, :availSlave => 0, :time => 0, :srvTime => 0}
                return {:status => :success, :data => data}
              when 'ticker'
                data = {:last => 0, :ask => 0, :bid => 0, :high => 0, :low => 0, :volume => 0, :time => 0, :srvTime => 0}
                return {:status => :success, :data => data}
              when 'depth'
                data = {:ask => [[0,0], [0,0]], :bid => [[0,0], [0,0]], :time => 0, :srvTime => 0}
                return {:status => :success, :data => data}
              when 'user_tran'
                user_tran = [{:tid => 0, :oid => 0, :master => 0, :slave => 0, :feeAmountMaster => 0, :feeAmountSlave => 0, :type => 0, :srvTime => 0}]
                data = {:user_tran => user_tran, :time => 0}
                return {:status => :success, :data => data}
              when 'open_ord'
                open_ord = [{:oid => 0, :price => 0, :amountOrig => 0, :amountPending => 0, :type => 0, :srvTime => 0}]
                data = {:open_ord => open_ord, :time => 0}
                return {:status => :success, :data => data}
              when 'cancel_ord'
                return {:status => :success, :data => {}}
              when 'place_ord'
                data = {:oid => 0, :srvTime => 0}
                return {:status => :success, :data => data}
            end
        end

        Globals.error(:syntax, "839136235")
      rescue StandardError => e
        #local_variables.each {|var| puts "#{var.to_s} is #{eval(var.to_s).class} and is equal to #{eval(var.to_s).inspect}" }
        Globals.error(:syntax, "518123976", e)
      end
    end

    def self.parseError(command, msg)
      #TODO parse nonce error and return as repeat
      case @@m_marketData[:exchange]
        when :bitstamp
=begin
{:price => ["Ensure that there are no more than 2 decimal places."]}
{:amount => ["Ensure that there are no more than 8 decimal places."]}
"{"error": {"amount": ["Ensure that there are no more than 8 decimal places."]}}"
"{"error": {"__all__": ["You have only 0.01228850 BTC available. Check your account balance for details."]}}"
"{"error": {"amount": ["Ensure this value is greater than or equal to 1E-8."]}}"
"{"error": {"price": ["Ensure that there are no more than 7 digits in total."]}}"
=end
          return {:status => :success, :data => {}} if command == 'cancel_ord' && msg == 'Order not found'
          return {:status => :design} if command == 'place_ord' && msg == {:__all__ => ["Minimum order size is $1"]}
          return {:status => :design} if command == 'place_ord' && msg == {:price => ["Ensure that there are no more than 2 decimal places."]}
          return {:status => :design} if command == 'place_ord' && msg == {:amount => ["Ensure that there are no more than 8 decimal places."]}
          return {:status => :repeat, :msg => msg} if command == 'place_ord' && msg.class == Hash && msg.has_key?(:__all__) && msg[:__all__].index {|x| x.class = String && x.include?("Check your account balance for details.")} != nil

        else
          Globals.error(:syntax, "839136435")
      end

      return {:status => :unknown, :msg => msg}
    end


  end
end
