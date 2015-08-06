# Bootstrap
# (sails.config.bootstrap)
#
# An asynchronous bootstrap function that runs before your Sails app gets lifted.
# This gives you an opportunity to set up your data model, run jobs, or perform some special logic.
#
# For more information on bootstrapping your app, check out:
# http://sailsjs.org/#/documentation/reference/sails.config/sails.config.bootstrap.html

later = require "later"
request = require "request-promise"
Promise = require "bluebird"

module.exports.bootstrap = (cb) ->

    # It's very important to trigger this callback method when you are finished
    # with the bootstrap!  (otherwise your server will never lift, since it's waiting on the bootstrap)
    
    validateTokenAsync = Promise
        .promisify waterlock.validator.validateToken
        .bind waterlock.validator

    save_attempt = (o) ->
        trade_attempt = 
            user: o.user.id
            instrument: o.instrument
            time: o.signals.ema5ema10.time
            ema5ema10: o.signals.ema5ema10.value
            rsi: o.signals.rsi.value
            stoch: o.signals.stoch.value
            status: o.signals.status
        TradeAttempt.create(trade_attempt)
        return o

    update_trades = (o) ->
        options = 
            url: "http://localhost:1337/api/trade/index"
            headers:
                "access-token": o.token
            qs:
                instrument: o.instrument
            json: true
        request options
            .then (open_trades) ->
                o.already_open = _.any(open_trades, (trade) ->
                        o.signals.ema5ema10.value and trade.side == o.signals.ema5ema10.value)
                open_trades.filter (trade) ->
                    o.signals.ema5ema10.value and trade.side != o.signals.ema5ema10.value 
            .map (trade) ->
                options =
                    url: "http://localhost:1337/api/trade/delete"
                    method: "delete"
                    headers:
                        "access-token": o.token
                    json:
                        trade_id: trade.id
                request(options)
                    .then (deleted_trade) -> console.log "trade deleted", deleted_trade
            return o

    place_order = (o) ->
        sails.log.debug "signals for instrument", o.instrument, o.signals.status
        signal = o.signals.status
        if o.already_open
            sails.log.debug "order already placed"
            return null
        return null if not signal
        options =
            url: "http://localhost:1337/api/order/create"
            method: "post"
            headers:
                "access-token": o.token
            json:
                instrument: o.instrument
                pip: o.pip
                precision: o.precision.length - 2
                side: signal
        request(options).then (response) ->
            sails.log.debug "placed order, got", response.body

    get_trade_status = (signals) ->
        all_equal = signals.ema5ema10.value and signals.ema5ema10.value == signals.rsi.value and signals.rsi.value == signals.stoch.value
        if all_equal
            signals.status = signals.ema5ema10.value
        else
            signals.status = false
        return signals
    
    get_signal = (stat, rawdata, token) ->
        options =
            url: "http://localhost:1337/api/signal/#{stat}"
            method: "post"
            json: rawdata
            headers:
                "access-token": token
        request(options)

    get_m5_stats = (token_and_rawdata) ->
        token = token_and_rawdata.token
        rawdata = token_and_rawdata.rawdata
        Promise.props {
            ema5ema10: get_signal "ema5ema10", rawdata, token
            rsi: get_signal "rsi", rawdata, token
            stoch: get_signal "stoch", rawdata, token
        }

    get_open_instruments = (token_and_user) ->
        token = token_and_user.token
        user = token_and_user.user
        options =
            url: "http://localhost:1337/api/instrument/index"
            qs:
                instruments: user.favorites
            json: true
            headers:
                "access-token": token
        request(options).then (instruments) ->
            open_instruments = instruments
                .filter (instrument) -> not instrument.halted
                .map (instrument) -> _.merge instrument, token_and_user
            return open_instruments

    get_rawdata = (token_and_instrument) ->
        token = token_and_instrument.token
        instrument = token_and_instrument.instrument
        options =
            url: "http://localhost:1337/api/instrument/rawdata"
            qs:
                name: instrument
                count: 25
                granularity: "M5"
            json: true
            headers:
                "access-token": token
        request options
            .then (rawdata) ->
                _.merge token_and_instrument, {rawdata: rawdata}

    get_token = (user) ->
        Jwt.find({owner: user.id, revoked: false})
            .then (tokens) ->
                Promise
                    .filter tokens, (token) ->
                        validateTokenAsync token.token
                            .then (user) -> true
                            .catch (error) ->
                                Jwt.destroy(id: token.id)
                                false
                    .then (valid) ->
                        token = if valid.length > 0 then valid[0].token else undefined
                        sails.log.debug "user logged in", user
                        {
                            token: token
                            user: user
                        }

    scheduled_function = ->
        User.find()
            .then (users) ->
                Promise
                    .map users, get_token
                    .map (user) -> 
                        return unless user.token?
                        get_open_instruments user
                            .then (instruments) ->
                                sails.log.debug "open instruments", instruments
                                Promise.map instruments, (instrument) -> 
                                    get_rawdata(instrument)
                                        .then get_m5_stats
                                        .then (m5_stats) ->
                                            Promise.props _.merge instrument, {signals: get_trade_status m5_stats}
                                                .then save_attempt
                                        .then update_trades
                                        .then place_order
            .then scheduled_function

    scheduled_function()    

    #schedule = later.parse.recur().every(5).minute()

    #later.setInterval scheduled_function, schedule

    cb()
