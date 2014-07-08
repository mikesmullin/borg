Ssh2 = require 'ssh2'
Logger = require './Logger'
DEBUG = false

module.exports = class Ssh
  constructor: (o, cb) ->
    return cb 'host is required' unless @host = o.host
    return cb 'pass or key is required' unless (@pass = o.pass) or (@key = o.key)
    @user = o.user || `whoami`
    @port = o.port || 22
    @connect cb
    return

  connect: (cb) ->
    Logger.out host: @host, 'ssh connecting...'
    @ssh  = new Ssh2()
    @ssh.once 'connect', =>
      Logger.out 'ssh connected'
    @ssh.once 'ready', =>
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
      privateKey: @key
    return

  cmd: (cmd, [o]..., cb) ->
    return cb 'cmd is required' unless cmd
    Logger.out host: @host, type: 'stdin', cmd
    @ssh.exec cmd, (err, stream) =>
      return cb err if err
      stream.on 'data', (data, extended) =>
        Logger.out host: @host, type: (if extended is 'stderr' then 'stderr' else 'stdout'), newline: false, data.toString().replace /[\r\n]{0,1}$/, "\n"
      stream.on 'data', o.data if typeof o?.data is 'function'
      stream.on 'end', =>
        Logger.out host: @host, 'ssh stream eof' if DEBUG
      stream.on 'close', =>
        Logger.out host: @host, 'ssh stream closed' if DEBUG
      stream.on 'exit', (code, signal) =>
        Logger.out host: @host, "ssh stream exit. code: #{code}#{if signal then "signal: #{signal}" else ""}" if DEBUG or code isnt 0
        cb code, signal if typeof cb is 'function'
    return

  put: (local, remote, cb) ->
    @sftp.fastPut local, remote, cb

  close: ->
    @ssh.end()
    return
