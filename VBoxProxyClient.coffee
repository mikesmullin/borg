net = require 'net'

module.exports =
class VBoxProxyClient
  constructor: ->
    @last_options = {}
    @events = {}
    #console.log 'client connecting to server'
    @socket = new net.Socket allowHalfOpen: false
    @socket.setTimeout 10*1000 # 10sec
    @socket.on 'end', ->
      #console.log 'socket ended'
      return
    @socket.on 'close', (err) ->
      #console.log 'socket closed due to a transmission error.' if err
      #console.log 'socket closed'
      return
    @socket.on 'error', (err) ->
      console.log 'socket error: '+ JSON.stringify err
      return
    buffer = ''
    @socket.on 'data', (buf) =>
      # remote can transmit messages split across several packets,
      # as well as more than one message per packet
      buffer += buf.toString()
      while (pos = buffer.indexOf("\u0000")) isnt -1 # we have a complete message
        recv = buffer.substr 0, pos
        buffer = buffer.substr pos+1
        data = JSON.parse recv
        #console.log JSON.stringify data, null, 2
        switch data.type
          when 'spawn'
            @events[data.pid] ||= {}
            for k, v of @last_options
              @events[data.pid][k] = v
            if typeof @events[data.pid]?.spawn is 'function'
              @events[data.pid].spawn data.pid
          when 'stdout'
            if typeof @events[data.pid]?.stdout is 'function'
              @events[data.pid].stdout data.data
          when 'stderr'
            if typeof @events[data.pid]?.stderr is 'function'
              @events[data.pid].stderr data.data
          when 'error'
            if typeof @events[data.pid]?.error is 'function'
              @events[data.pid].error data.data
          when 'close'
            if typeof @events[data.pid]?.close is 'function'
              @events[data.pid].close data.data
            delete @events[data.pid]

  connect: (host, port, cb) ->
    @socket.connect port, host, ->
      #console.log 'socket opened'
      cb() if typeof cb is 'function'
    return

  command: (args, o) ->
    @last_options = o
    @send args: args
    return

  close: (err) ->
    console.log err if err
    #console.log 'client sending FIN to server'
    @socket.end()
    #console.log 'client destroying socket to ensure no more i/o happens'
    @socket.destroy()
    return

  send: (data, cb) ->
    #console.log "send: #{data}"
    @socket.write JSON.stringify(data) + "\u0000", 'utf8', cb
    return

