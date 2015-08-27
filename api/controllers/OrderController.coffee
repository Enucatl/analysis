 # OrderController
 #
 # @description :: Server-side logic for managing orders
 # @help        :: See http://links.sailsjs.org/docs/controllers

module.exports = {

    create: (req, res, next) ->
        adr = 200
        pip = req.body.pip
        precision = req.body.precision
        instrument = req.body.instrument
        side = req.body.side
        stoploss = 0.1 * adr * pip
        takeprofit = 0.15 * adr * pip
        trailingstop = 24
        options = {}
        sails.log.debug "creating order for", instrument, adr, pip, precision, side, stoploss, takeprofit
        oandaHeaders req.user.account_type, req.user.oanda_token, options
        
        get_current_price = ->
            # get the current price and trade status
            options.url = "https://#{oandaServer req.user.account_type}/v1/prices"
            options.qs =
                    instruments: instrument
            oandaRequest options
                .then (body) ->
                    prices = body.prices[0]
                    sails.log.debug "the current prices are:", prices
                    if "status" in prices
                        # the presence of this parameter means that trading is
                        # halted, see:
                        # http://developer.oanda.com/rest-live/rates/#getCurrentPrices
                        throw new Error "trading for #{instrument} is now halted on oanda.com"
                    if side is "buy"
                        stoploss = prices.bid - stoploss
                        takeprofit = prices.ask + takeprofit
                    else if side is "sell"
                        stoploss = prices.ask + stoploss
                        takeprofit = prices.bid - takeprofit
                    else
                        throw new Error "#{side} MUST be either buy or sell"
                    return null

        get_current_balance = ->
            # get the current account balance in order to place an order sized
            # at 2% of the current balance
            options.url = "https://#{oandaServer req.user.account_type}/v1/accounts/#{req.user.account_id}"
            delete options.qs
            oandaRequest options
                .then (body) -> body.balance

        send_order = (balance) ->
            options.url = "https://#{oandaServer req.user.account_type}/v1/accounts/#{req.user.account_id}/orders"
            options.method = "post"
            options.form =
                instrument: instrument
                units: (0.02 * balance).toFixed(0)
                side: side
                type: "market"
                stopLoss: stoploss.toFixed precision
                takeProfit: takeprofit.toFixed precision
                trailingStop: trailingstop
            oandaRequest options

        get_current_price()
            .then get_current_balance
            .then send_order
            .then (body) -> res.json body
            .catch (error) -> next error.error

    index: (req, res, next) ->
        options =
            url: "https://#{oandaServer req.user.account_type}/v1/accounts/#{req.user.account_id}/orders"
        oandaHeaders req.user.account_type, req.user.oanda_token, options
        oandaRequest options
            .then (body) -> res.json body.orders
            .catch error -> next error.error

    update: (req, res, next) ->
        options =
            url: "https://#{oandaServer req.user.account_type}/v1/accounts/#{req.user.account_id}/orders/#{req.body.order_id}"
            method: "patch"
        accepted_keys = [
            "units"
            "price"
            "expiry"
            "lowerBound"
            "upperBound"
            "stopLoss"
            "takeProfit"
            "trailingStop"
        ]
        options.qs = _.pick req.body, accepted_keys
        oandaHeaders req.user.account_type, req.user.oanda_token, options
        oandaRequest options
            .then (body) -> res.json body
            .catch (error) -> next error.error

    delete: (req, res, next) ->
        options =
            url: "https://#{oandaServer req.user.account_type}/v1/#{req.user.account_id}/orders/#{req.body.order_id}"
            method: "delete"
        oandaHeaders req.user.account_type, req.user.oanda_token, options
        oandaRequest options
            .then (body) -> res.json body
            .catch (error) -> next error.error

}
