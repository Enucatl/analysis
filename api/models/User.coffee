
#User

#@module      :: Model
#@description :: This is the base user model
#@docs        :: http://waterlock.ninja/documentation

waterlock = require "waterlock"

module.exports =
    attributes: waterlock.models.user.attributes(
        oanda_token: 
            type: "string"
            required: "true"
        account_type:
            type: "string"
            required: "true"
        account_id:
            type: "string"
            required: "true"
        favorites: "array"
    )

    beforeCreate: waterlock.models.user.beforeCreate
    beforeUpdate: waterlock.models.user.beforeUpdate
    
    afterCreate: (newly_created_user, cb) ->
        # sails one-to-one associations are broken
        # see
        # http://stackoverflow.com/a/27752329
        if newly_created_user.auth?
            Auth.update({id: newly_created_user.auth}, {user: newly_created_user.id}).exec cb
        else
            cb()

    beforeDestroy: (values, cb) ->
        console.log "before destroy", values
        User.findOne values
            .exec (error, user) ->
                console.log "before destroy user found", error
                console.log "before destroy user found", user
                Auth.destroy user.auth
                    .exec (error, auth) ->
                        console.log "first destroying the auth", error, auth
                        if error?
                            cb error
                        else
                            cb()
