Logger = require './logger'
Ssh = require './ssh'
#spawn = require('child_process').spawn

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
    #console.log process.argv.slice(3)
    for node in process.argv.slice(3) when match = node.match(/^(.+?)(:(.+))?@(.+)$/)
      [nil, user, nil, pass, host] = match
      new Ssh user: user, pass: pass, host: host, cmd: 'date', (err) ->

  when 'ssh'
    console.log process.argv.slice(3)
  when 'deploy'
    console.log process.argv.slice(3)
