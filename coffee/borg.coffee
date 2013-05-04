ssh = require './ssh'
pkg = require '../package.json'
spawn = require('child_process').spawn

#process.stdout.write "Hello!\n"

switch process.argv[2]
  when '-V', '--version', 'version'
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
      #console.log "sshpass -p #{pass} ssh-copy-id #{user}@#{host}"
      child = spawn "ssh", ["-tt", "#{user}@#{host}"]#,
        #stdio: ['ignore', 'ignore', 'ignore']
      stdin = child.stdin
      child.stdout.on 'data', (data) ->
        console.log 'stdout: '+ data.toString()
        console.log 'hey something wrote out'
      child.stderr.on 'data', (data) ->
        console.log 'stderr: '+ data.toString()
      child.on 'close', (code, signal) ->
        console.log event: 'exit', code: code, signal: signal
        if code is 0
          #callback()
        else
          # exitCallback code

  when 'ssh'
    console.log process.argv.slice(3)
  when 'deploy'
    console.log process.argv.slice(3)


#ssh "date", (-> console.log "cb" ), ->
#  console.log "exit"

#process.exit 0
