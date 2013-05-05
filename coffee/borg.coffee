#spawn = require('child_process').spawn

class Debugger
  @started: new Date
  @log: (s) ->
    if console?
      current = new Date
      console.log "[#{(current - @started) / 1000}s] #{s}"

switch process.argv[2]
  when '-V', '--version', 'version'
    pkg = require '../package.json'
    console.log """
    borg v#{pkg.version} - by Mike Smullin <mike@smullindesign.com>

    """
  when '-h', '--help', 'help'
    switch process.argv[3]
      when 'rekey'
        console.log """
        Usage: borg rekey [options] <user:password@host ...>

        Options:

          -i  identity file path

        """
      when 'ssh'
        console.log ''
      when 'deploy'
        console.log ''
      else
        console.log """
        Usage: borg <command> [options] <host ...>

        Commands:

          rekey   copy ssh public key to authorized_hosts on remote host(s)
          ssh     bulk execute command on remote host(s)
          deploy  execute cookbook on remote host(s)

        Options:

          -h, --help     output usage information
          -V, --version  output version number

        """
  when 'rekey'
    console.log process.argv.slice(3)
    for node in process.argv.slice(3) when match = node.match(/^(.+?)(:(.+))?@(.+)$/)
      [nil, user, nil, pass, host] = match

      console.log 'trying'
      ssh = new (require 'ssh2')
      ssh.on 'connect', ->
        Debugger.log 'connected'
      ssh.on 'ready', ->
        Debugger.log 'ready'
        ssh.exec 'date', (err, stream) ->
          throw err if err
          stream.on 'data', (data, extended) ->
            Debugger.log "#{if extended is 'stderr' then 'stderr' else 'stdout'}: #{data}"
          stream.on 'end', ->
            Debugger.log 'stream EOF'
          stream.on 'close', ->
            Debugger.log 'stream closed'
          stream.on 'exit', (code, signal) ->
            Debugger.log "stream exit code #{code}, signal #{signal}"
            ssh.end()
      ssh.on 'error', (err) ->
        Debugger.log "Connection error: #{err}"
      ssh.on 'end', () ->
        Debugger.log "Connection end"
      ssh.on 'close', () ->
        Debugger.log "Connection closed"
      ssh.connect
        host: host
        port: 22
        username: user
        password: pass

  when 'ssh'
    console.log process.argv.slice(3)
  when 'deploy'
    console.log process.argv.slice(3)
