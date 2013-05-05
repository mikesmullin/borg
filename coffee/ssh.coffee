Ssh2 = require 'ssh2'
Logger = require './logger'

module.exports = class Ssh
  constructor: (o, cb) ->
    return cb 'host is required' unless @host = o.host
    return cb 'pass is required' unless @pass = o.pass
    return cb 'cmd is required'  unless @cmd  = o.cmd
    @user = o.user || 'root'
    @port = o.port || 22
    @ssh  = new Ssh2()
    Logger.out 'connecting'
    @ssh.on 'connect', ->
      Logger.out 'connected'
    @ssh.on 'ready', =>
      Logger.out 'ready'
      @ssh.exec @cmd, (err, stream) =>
        return cb err if err
        stream.on 'data', (data, extended) ->
          Logger.out "#{if extended is 'stderr' then 'stderr' else 'stdout'}: #{data}"
          o.stream_data.apply null, arguments if o.stream_data
        stream.on 'end', ->
          Logger.out 'stream EOF'
          o.stream_end if o.stream_end
        stream.on 'close', ->
          Logger.out 'stream closed'
          o.stream_close if o.stream_close
        stream.on 'exit', (code, signal) =>
          Logger.out "stream exit code #{code}, signal #{signal}"
          o.stream_exit.apply null, arguments if o.stream_exit
          @ssh.end()
          cb null
    @ssh.on 'error', (err) ->
      Logger.out "Connection error: #{err}"
      o.error.apply null, arguments if o.error
    @ssh.on 'end', ->
      Logger.out "Connection end"
      o.end if o.end
    @ssh.on 'close', ->
      Logger.out "Connection closed"
      o.close if o.close
    @ssh.connect
      host: @host
      port: @port
      username: @user
      password: @pass
