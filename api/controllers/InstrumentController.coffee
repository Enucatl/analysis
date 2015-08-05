 # InstrumentController
 #
 # @description :: Server-side logic for managing instruments
 # @help        :: See http://links.sailsjs.org/docs/controllers

module.exports =

    index: (req, res, next) ->
        options =
            url: "https://#{oandaServer req.user.account_type}/v1/instruments"
            qs:
                accountId: req.user.account_id
                fields: "instrument,displayName,pip,precision,maxTradeUnits,halted"
            json: true
        options.qs.instruments = req.param("instruments").join() if req.param("instruments")?
        oandaHeaders req.user.account_type, req.user.oanda_token, options
        oandaRequest options
            .then (body) -> res.json body.instruments
            .catch (error) -> next error.error

    rawdata: (req, res, next) ->
        options =
            url: "https://#{oandaServer req.user.account_type}/v1/candles"
            resolveWithFullResponse: true
            qs:
                instrument: req.param 'name'
                count: req.param 'count'
                granularity: req.param 'granularity'
                candleFormat: 'midpoint'
                dailyAlignment: 0
                alignmentTimezone: "Europe/Zurich"
        oandaHeaders req.user.account_type, req.user.oanda_token, options
        etag = memoryCache.get "etag"
        cached = memoryCache.get "cached"
        options.headers["If-None-Match"] = etag.etag if etag and cached
        oandaRequest options
            .then (response) ->
                if response.statusCode is 304
                    res.json cached.cached
                else
                    json = response.body.candles.filter (d) -> d.complete is true
                    memoryCache.set "etag", response.headers["etag"]
                    memoryCache.set "cached", json
                    res.json json
            .catch (error) -> next error.error

    historical: (req, res, next) ->
        options =
            url: "https://#{oandaServer req.user.account_type}/v1/candles"
            qs:
                instrument: req.param 'name'
                start: req.param 'start'
                end: req.param 'end'
                granularity: req.param 'granularity'
                candleFormat: 'midpoint'
                dailyAlignment: 0
                alignmentTimezone: "Europe/Zurich"
        oandaHeaders req.user.account_type, req.user.oanda_token, options
        oandaRequest options
            .then (body) -> body.candles
            .catch (error) -> next error.error

    ema5: (req, res) ->
        candles = req.body
        zmq_object =
            fun: "EMA"
            args:
                x: candles.map (d) ->
                    d.closeMid
                n: 5
        zmqUtils.send zmq_object, (data) ->
            sails.log.silly "ema5 answer data: #{data}"
            res.json rUtils.filter_NA(data).map (d) ->
                time: candles[d.index].time
                value: d.value

    ema10: (req, res) ->
        candles = req.body
        zmq_object =
            fun: "EMA"
            args:
                x: candles.map (d) ->
                    d.closeMid
                n: 10
        zmqUtils.send zmq_object, (data) ->
            sails.log.silly "ema10 answer data: #{data}"
            res.json rUtils.filter_NA(data).map (d) ->
                time: candles[d.index].time
                value: d.value

    rsi: (req, res) ->
        candles = req.body
        zmq_object =
            fun: "RSI"
            args:
                price: candles.map (d) ->
                    d.closeMid
                n: 14
        zmqUtils.send zmq_object, (data) ->
            sails.log.silly "rsi answer data: #{data}"
            res.json rUtils.filter_NA(data).map (d) ->
                time: candles[d.index].time
                value: d.value

    stoch: (req, res) ->
        candles = req.body
        zmq_object =
            fun: "stoch.json"
            args:
                data: candles
        zmqUtils.send zmq_object, (data) ->
            output = JSON.parse "#{data}"
            response = [{
                name: "fastK"
                values: output.fastK.map (d, i) ->
                    time: candles[i].time
                    value: d
            },{
                name: "fastD"
                values: output.fastD.map (d, i) ->
                    time: candles[i].time
                    value: d
            },{
                name: "slowD"
                values: output.slowD.map (d, i) ->
                    time: candles[i].time
                    value: d
            }]
            # return only values for which slowD is not NA
            res.json response.map (d) ->
                name: d.name
                values: d.values.filter (e, i) ->
                    response[2].values[i].value isnt "NA"

    adr: (req, res) ->
        candles = req.body.candles
        zmq_object =
            fun: "SMA"
            args:
                x: candles.map (d) ->
                    d.highMid - d.lowMid
                n: 14
        zmqUtils.send zmq_object, (data) ->
            sails.log.silly "adr answer data: #{data}"
            res.json rUtils.filter_NA(data).map (d) ->
                time: candles[d.index].time
                value: d.value / req.body.pip
