Ssh2 = require 'ssh2'
Logger = require './Logger'

# TODO: color output based on exit code. green if 0. else red

module.exports = class Ssh
  constructor: (o, cb) ->
    return cb 'host is required' unless @host = o.host
    return cb 'pass is required' unless @pass = o.pass
    @user = o.user || `whoami`
    @port = o.port || 22
    @ssh  = new Ssh2()

    # connect
    Logger.out host: @host, 'ssh connecting...'
    @ssh.on 'connect', =>
      Logger.out host: @host, 'ssh connected'
    @ssh.on 'ready', =>
      Logger.out host: @host, 'ssh authenticated'
      cb null, @ssh
    @ssh.on 'error', (err) =>
      Logger.out host: @host, "ssh error: #{err}"
    @ssh.on 'end', =>
      Logger.out host: @host, "ssh end"
    @ssh.on 'close', =>
      Logger.out host: @host, "ssh close"
    @ssh.connect
      host: @host
      port: @port
      username: @user
      password: @pass
    return

  cmd: (cmd, cb) ->
    return cb 'cmd is required' unless cmd
    Logger.out host: @host, type: 'info', "execute: #{@cmd}"
    @ssh.exec @cmd, (err, stream) =>
      return cb err if err
      stream.on 'data', (data, extended) =>
        # TODO: color-code based on both stderr/stdout and the exit status code 0 or non-zero
        Logger.out host: @host, type: (if extended is 'stderr' then 'err' else 'recv'), data
        o.stream_data.apply null, arguments if o.stream_data
      stream.on 'end', =>
        Logger.out host: @host, 'ssh stream eof'
        o.stream_end if o.stream_end
      stream.on 'close', =>
        Logger.out host: @host, 'ssh stream closed'
        o.stream_close if o.stream_close
      stream.on 'exit', (code, signal) =>
        Logger.out host: @host, "ssh stream exit. code: #{code}, signal: #{signal}"
        o.stream_exit.apply null, arguments if o.stream_exit
    return

  close: ->
    @ssh.end()
    return
