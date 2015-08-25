request = require "request-promise"
    .defaults json: true

RateLimiter = require("limiter").RateLimiter
limiter = new RateLimiter(1.9, 'second')
Promise = require "bluebird"
rateLimitAsync = Promise.promisify limiter.removeTokens
    .bind limiter

class OandaError extends Error
    constructor: (@message) ->
        # build an Error object with the data from the oanda api:
        # http://developer.oanda.com/rest-live/troubleshooting-errors/
        # https://github.com/petkaantonov/bluebird/blob/master/API.md#catchfunction-errorclassfunction-predicate-function-handler---promise
        @name = "OandaError"
        Error.captureStackTrace this, OandaError

send_request = (options) ->
    if not options.resolveWithFullResponse?
        request(options).then (body) ->
            throw new OandaError(body) if "code" in body
            return body
    else
        request(options)
            .then (response) ->
                throw new OandaError response.body if "code" in response.body
                return response
            .catch (reason) ->
                if reason.statusCode == 304
                    return reason
                else
                    throw new OandaError reason

module.exports = (options) ->
    rateLimitAsync(1)
        .then ->
            send_request(options)
