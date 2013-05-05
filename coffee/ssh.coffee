Ssh2 = require 'ssh2'
Logger = require './logger'

# TODO: color out put based on exit code. green if 0. else red

module.exports = class Ssh
  constructor: (o, cb) ->
    return cb 'host is required' unless @host = o.host
    return cb 'pass is required' unless @pass = o.pass
    return cb 'cmd is required'  unless @cmd  = o.cmd
    @user = o.user || 'root'
    @port = o.port || 22
    @ssh  = new Ssh2()
    #Logger.out host: @host, 'ssh connecting...'
    @ssh.on 'connect', =>
      Logger.out host: @host, 'ssh connected'
    @ssh.on 'ready', =>
      #Logger.out host: @host, 'ssh authenticated'
      Logger.out host: @host, type: 'info', "execute: #{@cmd}"
      @ssh.exec @cmd, (err, stream) =>
        return cb err if err
        stream.on 'data', (data, extended) =>
          Logger.out host: @host, type: (if extended is 'stderr' then 'err' else 'out'), data
          o.stream_data.apply null, arguments if o.stream_data
        stream.on 'end', =>
          #Logger.out host: @host, 'ssh stream eof'
          o.stream_end if o.stream_end
        stream.on 'close', =>
          #Logger.out host: @host, 'ssh stream closed'
          o.stream_close if o.stream_close
        stream.on 'exit', (code, signal) =>
          Logger.out host: @host, "ssh stream exit. code: #{code}, signal: #{signal}"
          o.stream_exit.apply null, arguments if o.stream_exit
          @ssh.end()
    @ssh.on 'error', (err) =>
      Logger.out host: @host, "ssh error: #{err}"
      o.error.apply null, arguments if o.error
    @ssh.on 'end', =>
      #Logger.out host: @host, "ssh end"
      o.end if o.end
    @ssh.on 'close', =>
      Logger.out host: @host, "ssh close"
      o.close if o.close
      cb null
    @ssh.connect
      host: @host
      port: @port
      username: @user
      password: @pass
