$LOAD_PATH.unshift File.dirname(__FILE__)
require 'api_net'
require 'api_tl'
require 'api_syntax'

module API
  mattr_accessor :m_idMarket

  mattr_accessor :m_httpHardTimeout
  mattr_accessor :m_thrWaitTimeout
  mattr_accessor :m_thrKillTimeout
  mattr_accessor :m_isDBlog
  mattr_accessor :m_isVservBash
  #and other bitstamp params

  mattr_accessor :m_threads
  mattr_accessor :m_apiModel
  mattr_accessor :m_virtualTimestamp    #replaced by fireTurnTime
  mattr_accessor :m_isLocalServer

  @@m_threads = []   #[[:idTL, :thread], [], ...]
  @@m_apiModel = :dbDirect # dbPar, dbSeq, dbDirect
  @@m_isLocalServer = false

  @@m_httpHardTimeout = 10

  def self.init(client, idMarket, httpEngine, apiModel, isDBlog)
    Globals::Logger.initialize

    @@m_apiModel = apiModel
    @@m_isDBlog = isDBlog

    @@m_idMarket = idMarket
    Market.enthrone_market(idMarket)
    marketData, exchg, coinMaster, coinSlave = Market.get_market

    @@m_isLocalServer = true    if marketData.has_key?(:isLocalServer) && marketData[:isLocalServer] == true

    Syntax.init(apiModel)
    TL.init(client)
    Internety.init(httpEngine)

    puts 'shiiit'
  end



  def self.set_query_time(virtualTimestamp)
    @@m_virtualTimestamp = virtualTimestamp
  end



  def self.get_virtual_timestamp
    isLocalServer = @@m_isLocalServer

    if isLocalServer
      return @@m_virtualTimestamp
    else
      #@@m_virtualTimestamp = Time.now.to_f
      return @@m_virtualTimestamp
    end
  end



  def self.query(command, optHash, fireTurnTime)
    #not applicable to :dbPar
    if @@m_apiModel == :dbPar
      Globals.error(:design, "1583287964")
    end

    if @@m_apiModel == :dbDirect
      begin
        timeStart = Time.now.to_f
        resp = {}
        resp = Vserv.quick_step(fireTurnTime, command.to_s, optHash)
        resp[:timeframe] = {:fire_time => timeStart, :resp_time => Time.now.to_f}
        resp[:time] = fireTurnTime
        return resp
      rescue StandardError => e
        Globals.error(:design, "5342173178", e)
      end
    end

    isLocalServer = @@m_isLocalServer

    idTL = 0
    idTL = TL.createTL(command, optHash, fireTurnTime) if @@m_isDBlog

    uri = Syntax.getURI(command.to_s, optHash)
    TL.saveURI(idTL, uri) if @@m_isDBlog

    #check transaction limit against exchange. Possible only when logging is enabled
    if @@m_isDBlog
      trans_limit = Syntax.getQueryLimit
      if !TL.checkQueryLimit(idTL, trans_limit, fireTurnTime)
        #return {:status => :repeat, :msg => 'query limit reached', :idTL => idTL}
        return getTL(idTL)
      end
    end

    timeStart = Time.now.to_f
    resp = {}
    if !isLocalServer
      resp = Internety.http(uri, @@m_httpHardTimeout)
      resp[:timeframe] = {:fire_time => timeStart, :resp_time => Time.now.to_f}
    else
      begin
        resp = {:ctype => 'application/json', :data => Vserv.step(fireTurnTime, uri[:bitstamp_command], uri[:options])}
        resp[:timeframe]   = {:fire_time => timeStart, :resp_time => Time.now.to_f}
        resp[:http_time]   = resp[:timeframe][:resp_time] - resp[:timeframe][:fire_time]
        resp[:total_time]  = resp[:http_time]
      rescue StandardError => e
        Globals.error(:design, "5342173178", e)
      end
    end

    parsed = Syntax.parse(command, optHash, resp, fireTurnTime)
    if idTL > 0
      parsed[:idTL] = idTL
    end
    parsed[:timeframe] = resp[:timeframe]
    parsed[:time] = fireTurnTime

    TL.saveResp(idTL, resp, parsed) if @@m_isDBlog
    return parsed
  end



  def self.forked(command, optHash, idTL, fireTurnTime)
    #not applicable to :dbDirect and :dbSeq
    if @@m_apiModel != :dbPar
      return
    end

    isLocalServer = @@m_isLocalServer

    uri = Syntax.getURI(command.to_s, optHash)
    TL.saveURI(idTL, uri)

    trans_limit = Syntax.getQueryLimit
    if !TL.checkQueryLimit(idTL, trans_limit, fireTurnTime)
      return
    end

    timeStart = Time.now.to_f
    resp = {}
    if !isLocalServer
      resp = Internety.http(uri, @@m_hardTimeout)
      resp[:timeframe] = {:fire_time => timeStart, :resp_time => Time.now.to_f}
    else
      begin
        resp = {:ctype => 'application/json', :data => Vserv.step(fireTurnTime, uri[:bitstamp_command], uri[:options])}
        resp[:timeframe] = {:fire_time => timeStart, :resp_time => Time.now.to_f}
        resp[:http_time] = resp[:timeframe][:resp_time] - resp[:timeframe][:fire_time]
      rescue StandardError => e
        Globals.error(:design, "5342173179", e)
      end
    end

    parsed = Syntax.parse(command, optHash, resp, fireTurnTime)
    parsed[:time] = fireTurnTime
    parsed[:timeframe] = resp[:timeframe]
    parsed[:idTL] = idTL

    TL.saveResp(idTL, resp, parsed)
  end



  def self.queryParId(command, optHash, fireTurnTime)
    #not applicable to :dbDirect and :dbSeq
    if @@m_apiModel != :dbPar
      return 0
    end

    idTL = 0
    idTL = TL.createTL(command.to_s, optHash, fireTurnTime)

    @@m_threads << [:idTL => idTL, :thread_fire_time => Time.now.to_f, :thr => Thread.new {forked(command.to_s, optHash, idTL, fireTurnTime)}]

    return idTL
  end



  def self.wait_threads(timestamp)
    #not applicable to :dbDirect and :dbSeq
    if @@m_apiModel != :dbPar
      return
    end

    threads.each do |item|
      thr = item[:thr]
      diffWait = Time.now.to_f - timestamp
      diffHard = Time.now.to_f - item[:thread_fire_time]
      if diffWait > 0
        if thr.join(diffWait) == nil
          if diffHard > @@m_thrKillTimeout
            #we do not want to interrupt TL.saveResp
            TL.lockTL
            thr.kill
            TL.unlockTL
          end
        end
      else
        if diffHard > @@m_thrKillTimeout
          #we do not want to interrupt TL.saveResp
          TL.lockTL
          thr.kill
          TL.unlockTL
        end
      end
    end

  end



  def self.queryParFn(idTL)
    #not applicable to :dbDirect and :dbSeq
    if @@m_apiModel != :dbPar
      Globals.error(:design, "1846528381")
    end

    return TL.getTL(idTL)
    #return status, command, optHash, fireTurnTime, parsed_data...
  end






  #+optional {:bidDepth => 0, :askDepth => 0} - price for 100USD equivalent - for cryptsy, where you have 20 depth records in ticker
  def self.ticker
    inp = {}
    out = {:last => 0, :ask => 0, :bid => 0, :high => 0, :low => 0, :volume => 0, :time => 0}

    query('ticker', {}, get_virtual_timestamp)
  end


  def self.depth
    inp = {}
    out = {:time => 0, :ask => [[0,0], [0,0]], :bid => [[0,0], [0,0]]}

    query('depth', {}, get_virtual_timestamp)
  end


  #+optional {:totalMaster => 0, :totalSlave => 0}
  def self.balance
    inp = {}
    out = {:availMaster => 0, :availSlave => 0, :time => 0}

    query('balance', {}, get_virtual_timestamp)
  end


  def self.user_tran(optHash = {})
    inp = {:offset => 0, :limit => 100, :sort => 'DESC'}
    out = [{:tid => 0, :oid => 0, :master => 0, :slave => 0, :feeAmountMaster => 0, :feeAmountSlave => 0, :type => 0, :srvTime => 0}]

    query('user_tran', optHash, get_virtual_timestamp)
  end


  def self.open_ord
    inp = {}
    out = [{:oid => 0, :price => 0, :amountOrig => 0, :amountPending => 0, :type => 0, :srvTime => 0}]

    query('open_ord', {}, get_virtual_timestamp)
  end


  def self.place_ord(optHash)
    inp = {:price => 0, :amount => 0, :type => 0}
    out = {:oid => 0, :srvTime => 0, :error => :fail}

    query('place_ord', optHash, get_virtual_timestamp)
  end


  def self.cancel_ord(optHash)
    inp = {:oid => 0}
    out = {:error => :success}

    query('cancel_ord', optHash, get_virtual_timestamp)
  end

=begin
  OPERATIONS.each do |operation|
    class_eval %{
          def get_pair_#{operation}_json(pair)
            get_pair_operation_json pair, "#{operation}"
          end
        }

    API::CURRENCY_PAIRS.each do |pair|
      class_eval %{
            def get_#{pair}_#{operation}_json
              get_pair_#{operation}_json "#{pair}"
            end
          }
    end
  end
=end

end


#API module test
#realtime - ci sa pridanie orderu hned prejavi na open_orders - ci je market server realtime
#   tj po nejakom write overit ci sedi info z read
#otestovat vsetky volania - vyrobit par orderov a potom ich porusit
#niektore aj kupit a otestovat ako velmi sa to prejavilo






















=begin
  def self.ticker
    inp = {}
    out = {:last => 0, :ask => 0, :bid => 0, :high => 0, :low => 0, :volume => 0, :time => 0}
  end

  def self.depth
    inp = {}
    out = {:time => 0, :ask => [[0,0], [0,0]], :bid => [[0,0], [0,0]]}
  end

  def self.balance
    inp = {}
    out = {:availMaster => 0, :availSlave => 0, :time => 0}
  end

  def self.user_tran
    inp = {:offset => 0, :limit => 100, :sort => 'ASC'}
    out = [{:tid => 0, :oid => 0, :time => 0, :usd => 0, :btc => 0, :feeAmount => 0, :type => 0}]
  end

  def self.open_ord
    inp = {}
    out = [{:oid => 0, :time => 0, :price => 0, :amountOrig => 0, :amountPending => 0, :type => 0}]
  end

  def self.place_ord
    inp = {:price => 0, :amount => 0, :type => 0}
    out = {:oid => 0, :error => :fail}
  end

  def self.cancel_ord
    inp = {:oid => 0}
    out = {:error => :success}
  end
=end