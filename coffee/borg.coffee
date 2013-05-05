Logger = null
Ssh    = null
async  = null

class Borg
  @nodes: []
  @args: []
  @options: {}
  @cmd: {}

  constructor: (cmd) ->
    last_option = null
    for arg in process.argv.slice(3)
      if match = arg.match(/^(.+?)(:(.+))?@(.+)$/)
        Borg.nodes.push user: match[1], pass: match[3], host: match[4]
      else
        if arg[0] is '-'
          Borg.options[last_option = arg.split(/^--?/)[1]] = true
        else if last_option isnt null
          Borg.options[last_option] = arg
          last_option = null
        else
          Borg.args.push arg
    Borg[Borg.cmd = cmd]()
    console.log cmd: Borg.cmd, nodes: Borg.nodes, args: Borg.args, options: Borg.options

  @rekey: ->
    #new Ssh user: user, pass: pass, host: host, cmd: 'ping -c3 google.com', (err) ->

  @assimilate: ->
    #new Ssh user: user, pass: pass, host: host, cmd: 'ping -c3 google.com', (err) ->

  @command: (host) ->
    #new Ssh user: user, pass: pass, host: host, cmd: 'ping -c3 google.com', (err) ->


switch cmd = process.argv[2]
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


