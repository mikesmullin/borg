Logger = null
Ssh    = null
async  = null

class Borg
  constructor: (cmd) ->
    nodes = []
    options = {}
    args = []
    last_option = null
    for arg in process.argv.slice(3)
      if match = arg.match(/^(.+?)(:(.+))?@(.+)$/)
        nodes.push user: match[1], pass: match[3], host: match[4]
      else
        if arg[0] is '-'
          options[last_option = arg.split(/^--?/)[1]] = true
        else if last_option isnt null
          options[last_option] = arg
          last_option = null
        else
          args.push arg
    console.log cmd: cmd, nodes: nodes, options: options, args: args
    flow = new async
    for own node in nodes
      ((node) ->
        flow.parallel (next) ->
          Borg[cmd](node, options, next)
      )(node)
    flow.go (err, results...) ->
      if err
        #process.stderr.write err+"\n"
        Logger.out 'aborted with error.'
        #process.exit 1
      else
        Logger.out 'all done.'
        #process.exit 0

  @rekey: (node, options, cb) ->
    #new Ssh user: user, pass: pass, host: host, cmd: 'ping -c3 google.com', (err) ->

  @assimilate: (node, options, cb) ->
    #new Ssh user: user, pass: pass, host: host, cmd: 'ping -c3 google.com', (err) ->

  @command: (node, options, cb) ->
    new Ssh user: node.user, pass: node.pass, host: node.host, cmd: options.c, (err) ->
      Logger.out host: node.host, type: 'err', err if err
      cb err

switch cmd = process.argv[2]
  when '-V', '--version', 'version'
    pkg = require '../package.json'
    console.log """
    borg v#{pkg.version}

    """
  when '-h', '--help', 'help'
    switch process.argv[3]
      when 'rekey'
        console.log """
        Usage: borg rekey [options] <user:password@host ...>

        Options:

          -i  identity file path

        """
      when 'assimilate'
        console.log """
        Usage: borg assimilate [options] <user:password@host ...>

        Options:

          -r, --role  assign each node the following role

        """
      when 'command'
        console.log """
        Usage: borg command [options] <user:password@host ...>

        Options:

          --sudo              use `sudo -i`
          -u=<user>           use `sudo -iu`
          -c=<shell_command>  command to execute

        """
      else
        console.log """
        Usage: borg <command> [options] <host ...>

        Commands:

          rekey       copy ssh public key to authorized_hosts on remote host(s)
          assimilate  bootstrap and cook remote host(s)
          command     bulk execute command on remote host(s)

        Options:

          -h, --help     output usage information
          -V, --version  output version number

        """
  when 'rekey', 'assimilate', 'command'
    Logger = require './logger'
    Ssh = require './ssh'
    async = require 'async2'
    Borg cmd
