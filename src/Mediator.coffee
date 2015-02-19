class Mediator

  constructor: (obj, @cascadeChannels=false) ->
    @channels = {}
    if obj instanceof Object then @installTo obj
    else if obj is true then @cascadeChannels=true

  # ## Subscribe to a topic
  #
  # Parameters:
  #
  # - (String) topic      - The topic name
  # - (Function) callback - The function that gets called if an other module
  #                         publishes to the specified topic
  # - (Object) context    - The context the function(s) belongs to
  on: (channel, fn, context=@) ->

    @channels[channel] ?= []
    that = @

    if channel instanceof Array
      @on id, fn, context for id in channel
    else if typeof channel is "object"
      @on k,v,fn for k,v of channel
    else
      return false unless typeof channel is "string"
      subscription = { context: context, callback: fn or -> }
      (
        attach: -> that.channels[channel].push subscription; @
        detach: -> Mediator._rm that, channel, subscription.callback; @
        pipe:   -> that.pipe.apply that, [channel, arguments...]; @
      ).attach()

  # ## Unsubscribe from a topic
  #
  # Parameters:
  #
  # - (String) topic      - The topic name
  # - (Function) callback - The function that gets called if an other module
  #                         publishes to the specified topic
  off: (ch, cb) ->
    switch typeof ch
      when "string"
        Mediator._rm @,ch,cb if typeof cb is "function"
        Mediator._rm @,ch    if typeof cb is "undefined"
      when "function"  then Mediator._rm @,id,ch      for id of @channels
      when "undefined" then Mediator._rm @,id         for id of @channels
      when "object"    then Mediator._rm @,id,null,ch for id of @channels
    @

  _getTasks = (data, channel, originalChannel, ctx) ->
    subscribers = ctx.channels[channel] or []
    for sub in subscribers then do (sub) ->
      (next) ->
        try
          if util.hasArgument sub.callback, 3
            sub.callback.apply sub.context, [data, originalChannel, next]
          else
            next null, sub.callback.apply sub.context, [data, originalChannel]
        catch e
          next e

  # ## Publish an event
  #
  # Parameters:
  # - (String) topic             - The topic name
  # - (Object) data              - The data that gets published
  # - (Funtction)                - callback method
  emit: (channel, data, cb=(->), originalChannel=channel) ->

    if typeof data is "function"
      cb  = data
      data = undefined
    return false unless typeof channel is "string"

    tasks = _getTasks data, channel, originalChannel, @

    util.runSeries tasks,((errors, results) ->
      if errors
        e = new Error (x.message for x in errors when x?).join '; '
      cb e), true

    if @cascadeChannels and (chnls = channel.split '/').length > 1
      o = originalChannel if @emitOriginalChannels
      @emit chnls[0...-1].join('/'), data, cb, o
    @

  # ## Send a task
  #
  # Parameters:
  # - (String) topic             - The topic name
  # - (Object) data              - The data that gets published
  # - (Function)                 - callback method
  send: (channel, data, cb=->) ->

    if typeof data is "function"
      cb  = data
      data = undefined
    return false unless typeof channel is "string"
    tasks = _getTasks data, channel, channel, @

    util.runFirst tasks,((errors, result) ->
      if errors
        e = new Error (x.message for x in errors when x?).join '; '
        cb e
      else
        cb null, result), true
    @

  # ## Install Pub/Sub functions to an object
  installTo: (obj,force) ->
    if typeof obj is "object"
      for k,v of @
        if force then obj[k] = v
        else obj[k] ?= v
    @

  @_redirect: (method, src, target, mediator) ->

    if target instanceof Mediator
      mediator = target; target = src

    return Mediator._redirect.call @, method, src, target, @ unless mediator?

    # prevent cycles
    return @ if mediator is @ and src is target

    @on src, -> mediator[method].apply mediator, [target, arguments...]

    @

  pipe: (src, target, mediator) ->
    Mediator._redirect.apply @, ['emit', arguments...]


  forward: (src, target, mediator) ->
    Mediator._redirect.apply @, ['send', arguments...]


  @_rm: (o, ch, cb, ctxt) ->
    return unless o.channels[ch]?
    o.channels[ch] = (s for s in o.channels[ch] when (
      if cb?
        s.callback isnt cb
      else if ctxt?
        s.context isnt ctxt
      else
        s.context isnt o
    ))
