#transaction log

module API
  module TL
    mattr_accessor :m_lock
    mattr_accessor :m_dbConn
    mattr_accessor :m_idBInstance

    #SQL paralell client? - jeden spolocny, alebo co thread to klient
    #staci nam jedna konekcia, lebo vsetko s klientom sa robi za lockom - teda sekvencne

=begin
    validity == 0 : header inserted
    validity == 1 : ready for request
    validity == 2 : request sent
    validity == 4 : data uploaded
    validity == 8 : error info is present
=end

    def self.init(client)
      @@m_dbConn = client
      @@m_lock = Mutex.new
      @@m_idBInstance = 0
    end

    #such idBInstance is known after API.init (we need to call API.init before creating a bot)
    def self.set_bot(idBInstance)
      @@m_idBInstance = idBInstance
    end

    def self.createTL(command, optHash, fireTurnTime)
      client = @@m_dbConn
      idBInstance = @@m_idBInstance

      idBInstanceStr = (idBInstance==0 ? idBInstance.to_s : 'NULL')

      #create DB record
      validity = 0
      parsed = {:status => :pending, :msg_aoh => [], :time => fireTurnTime}
      query = "
INSERT INTO `trans_log` (idBInstance, `reqTime`, `reqTimeUnix`, `command`, `options_json`, `parsed_yaml`, `validity`) VALUES
(#{idBInstanceStr}, '#{fireTurnTime.to_s(:db)}', #{fireTurnTime.to_s}, '#{command.to_s}', '#{optHash.to_json}', '#{parsed.to_yaml}', #{validity})"
      client.query(query)
      affe = client.affected_rows
      idTL = client.last_id
      if !(affe == 1 && idTL > 0)
        Globals.error(:component_fail, "6178511563", {:client => Marshal.dump(client), :affe => affe, :idTL => idTL})
      end

      return idTL
    end

    def self.saveURI(idTL, uri)
      lockTL
      client = @@m_dbConn
      result = true

      begin
        #Marshal.load(YAML.load(Marshal.dump({:uri => URI.parse('https://www.cryptsy.com/api')}).to_yaml))
        query = ''
        query = "
UPDATE `trans_log` SET
`uri_yaml`=#{Marshal.dump(uri).to_yaml}
WHERE idTL = #{idTL}"
        client.query(query)
      rescue Mysql2::Error => e
        result = false
        unlockTL
        Globals.error(:component_fail, "4627201496", {:client => Marshal.dump(client), :query => query, :idTL => idTL, :exception => e})
        return result
      rescue StandardError => e
        result = false
        unlockTL
        Globals.error(:design, "4627201496", {:client => Marshal.dump(client), :query => query, :idTL => idTL, :exception => e})
        return result
      end

      unlockTL
      return result
    end

    def self.checkQueryLimit(idTL, trans_limit, fireTurnTime)
      lockTL
      client = @@m_dbConn
      idBInstance = @@m_idBInstance
      result = true

      begin
        query = ''
        query = "SELECT validity, parsed_yaml FROM `trans_log` WHERE idTL = #{idTL}"
        rs = client.query(query, :symbolize_keys => true)
        tl_item = rs.each[0]
        validity = tl_item[:validity]
        parsed = YAML.load(tl_item[:parsed_yaml])

        if idBInstance != 0
          #trans_limit = {:queries => 600, :per_seconds => 600}
          #check query limit - notice that we are counting only ones with validity 1 flag set - only those who were able to send HTTP request
          query = ''
          query = "
SELECT COUNT(idTL) AS count600 FROM `trans_log`
WHERE idBInstance = #{idBInstance}
AND validity % 2 == 1
AND reqTimeUnix > #{(fireTurnTime-trans_limit[:per_seconds]).to_s}"
          rs = client.query(query, :symbolize_keys => true)
          count600 = rs.each[0][:count600]
          if (count600.to_i > trans_limit[:queries])
            result = false
            currentError = {:error => 'ERR_TRANSACTION_LIMIT', :errMsg => "Transaction limit reached, #{count600} > #{trans_limit[:queries]}"}
            parsed[:msg_aoh] << currentError
            parsed[:status] = :repeat
            validity = validity | 8
          else
            result = true
            validity = validity | 1
          end
        else
          result = true
          validity = validity | 1
        end

        #save information to db TL
        parsed[:idTL] = idTL
        query = "
UPDATE `trans_log` SET
`parsed_yaml` ='#{parsed.to_yaml}'
,`validity`   = #{validity}
WHERE idTL = #{idTL}"
        client.query query

      rescue Mysql2::Error => e
        result = false
        unlockTL
        Globals.error(:component_fail, "62890644329", {:client => Marshal.dump(client), :query => query, :idTL => idTL, :exception => e})
        return result
      rescue StandardError => e
        result = false
        unlockTL
        Globals.error(:design, "62890644329", {:client => Marshal.dump(client), :query => query, :idTL => idTL, :exception => e})
        return result
      end

      unlockTL
      return result
    end

    def self.saveResp(idTL, resp, parsed)
      lockTL
      client = @@m_dbConn
      result = true

      begin
        query = ''
        query = "SELECT validity, parsed_yaml FROM `trans_log` WHERE idTL = #{idTL}"
        rs = client.query(query, :symbolize_keys => true)
        tl_item = rs.each[0]
        validity = tl_item[:validity]
        parsed_yet = YAML.load(tl_item[:parsed_yaml])

        #Marshal.load(YAML.load(Marshal.dump({:uri => URI.parse('https://www.cryptsy.com/api')}).to_yaml))
        validity = validity | 2 #reuqest sent
        validity = validity | 4 #data uploaded

        #merge status
        if parsed_yet[:status] != :pending
          parsed[:status] = parsed_yet[:status]
        end
        #merge messages
        if parsed_yet.has_key?(:msg_aoh)
          if !parsed.has_key?(:msg_aoh)
            parsed[:msg_aoh] = []
          end

          parsed[:msg_aoh].concat(parsed_yet[:msg_aoh])
        end
        parsed[:time] = parsed_yet[:time]

        query = ''
        query = "
UPDATE `trans_log` SET
`http_time`       = #{resp[:http_time]}
`total_time`      = #{resp[:total_time]}
,`contentType`    ='#{resp[:ctype]}'
,`contentLength`  = #{resp[:data].length}
,`content_yaml`   ='#{Marshal.dump(resp[:data]).to_yaml}'
,`parsed_yaml`    ='#{parsed.to_yaml}'
,`status`         ='#{parsed[:status]}'
,`validity`       = #{validity}
WHERE idTL = #{idTL}"
        client.query(query)

      rescue Mysql2::Error => e
        result = false
        unlockTL
        Globals.error(:component_fail, "2656024263", {:client => Marshal.dump(client), :query => query, :idTL => idTL, :exception => e})
        return result
      rescue StandardError => e
        result = false
        unlockTL
        Globals.error(:design, "2656024263", {:client => Marshal.dump(client), :query => query, :idTL => idTL, :exception => e})
        return result
      end

      unlockTL
      return result
    end

    def self.lockTL(deadlockTime = 0)
      firstAttempt = Time.now

      while !@@m_lock.try_lock
        sleep(0.001)
        if deadlockTime > 0
          diff = Time.now - firstAttempt
          if diff > deadlockTime
            #if we wait longer than deadlockTime fire :design error
            Globals.error(:design, "741681874")
          end
        end
      end
    end

    def self.unlockTL
      begin
        @@m_lock.unlock
      rescue ThreadError => e
      end
    end

    def self.getTL(idTL)
      client = @@m_dbConn

      begin
        query = ''
        query = "SELECT validity, parsed_yaml, command, options_json FROM `trans_log` WHERE idTL = #{idTL}"
        rs = client.query(query, :symbolize_keys => true)
        if rs.count == 1
          tl_item = rs.each[0]
          validity = tl_item[:validity]
          parsed = YAML.load(tl_item[:parsed_yaml])
          command = tl_item[:command]
          optHash = JSON.parse(tl_item[:options_json], :symbolize_names => true)

          parsed[:command] = command
          parsed[:optHash] = optHash

          return parsed
        else
          #nothing else but 1 is bad for us => return error
          parsed ||= {}
          if parsed == {}
            status = :fail # :repeat, :pending, :unknown, :success
            fireTurnTime = 0
            parsed.replace({:status => status, :data => 0, :time => fireTurnTime, :command => :nope, :optHash => {}, :idTL => idTL})
            parsed[:timeframe] = {:fire_time => 0, :resp_time => 0}
          end

          return parsed
        end

      rescue Mysql2::Error => e
        Globals.error(:component_fail, "32478028047", {:client => Marshal.dump(client), :query => query, :idTL => idTL, :exception => e})
      rescue StandardError => e
        Globals.error(:design, "32478028047", {:client => Marshal.dump(client), :query => query, :idTL => idTL, :exception => e})
      end

      return nil
    end

    #read and write actions are isolated - pending_idTL can be pending_read_actions or pending_write_actions
    def self.getPending(pending_idTL, ids = [])
      response = {}

      pending_idTL.keep_if do |idTL|
        tl = getTL(idTL)
        Globals.error(:design, "3236188431") if tl == nil

        if !response.has_key? tl[:time]
          response[tl[:time]] = {}
        end
        response[tl[:time]][tl[:command].to_sym] = tl

        tl[:status] == :pending
      end

      ids.each do |idTL|
        tl = getTL(idTL)
        Globals.error(:design, "3236188431") if tl == nil

        if !response.has_key? tl[:time]
          response[tl[:time]] = {}
        end
        response[tl[:time]][tl[:command].to_sym] = tl

        #TODO co ak je uz tu :repeat? - kde sa to pusti znova, ked je vrateny repeat?
        if tl[:status] == :pending
          pending_idTL << idTL
        end
      end

      return response
    end
  end
end