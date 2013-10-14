Ssh2 = require 'ssh2'
Logger = require './Logger'

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
      Logger.out 'ssh connected'
    @ssh.on 'ready', =>
      Logger.out 'ssh authenticated'
      @ssh.sftp (err, sftp) =>
        return cb err if err
        @sftp = sftp
        @sftp.on 'end', ->
          Logger.out 'ssh sftp closed'
        Logger.out 'ssh sftp session created'
        cb()
    @ssh.on 'error', (err) =>
      Logger.out "ssh error: #{err}"
    @ssh.on 'end', =>
      Logger.out 'ssh end'
    @ssh.on 'close', =>
      Logger.out 'ssh close'
    @ssh.connect
      host: @host
      port: @port
      username: @user
      password: @pass
    return

  cmd: (cmd, o, cb) ->
    return cb 'cmd is required' unless cmd
    Logger.out host: @host, type: 'info', "execute: #{cmd}"
    @ssh.exec cmd, (err, stream) =>
      return cb err if err
      stream.on 'data', (data, extended) =>
        # TODO: color-code based on both stderr/stdout and the exit status code 0 or non-zero
        Logger.out host: @host, type: (if extended is 'stderr' then 'err' else 'recv'), data
      stream.on 'data', o.data if typeof o.data is 'function'
      stream.on 'end', =>
        Logger.out host: @host, 'ssh stream eof'
      stream.on 'close', =>
        Logger.out host: @host, 'ssh stream closed'
      stream.on 'exit', (code, signal) =>
        Logger.out host: @host, "ssh stream exit. code: #{code}, signal: #{signal}"
        cb code, signal
    return

  put: (local, remote, cb) ->
    @sftp.fastPut local, remote, cb

  close: ->
    @ssh.end()
    return
