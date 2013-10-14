global.Logger = require './Logger'
global.die = (reason) ->
  Logger.out type: 'err', reason
  console.trace()
  process.exit 1
  return
Ssh    = require './Ssh'
async = require 'async2'

# TODO: support:
# borg cmd --sudo u:p@localhost:223 -- test blah
# borg cmd --sudo u:p@localhost:223 test blah
# borg assimilate developer:tunafish@10.1.10.24:22

module.exports =
class Borg
  constructor: (cmd) ->
    targets = []
    options = {}
    args = []
    last_option = null
    for arg in process.argv.slice(3)
      if match = arg.match(/^(.+?)(:(.+))?@(.+?)(:(.+))?$/)
        targets.push user: match[1], pass: match[3], host: match[4], port: match[6]
      else
        if arg[0] is '-'
          options[last_option = arg.split(/^--?/)[1]] = true
        else if last_option isnt null
          options[last_option] = arg
          last_option = null
        else
          args.push arg
    if options.sudo then options.c = "sudo #{options.c}" # TODO: double-escape quotes, multiple commands, etc.
    #console.log cmd: cmd, targets: targets, options: options, args: args
    flow = new async
    for own k, target of targets
      ((target) ->
        flow.parallel (next) ->
          Borg[cmd] target, options, next
      )(target)
    flow.go (err, results...) ->
      if err
        #process.stderr.write err+"\n"
        Logger.out 'aborted with error.'
        #process.exit 1
      else
        Logger.out 'all done.'
        #process.exit 0

  @rekey: (target, options, cb) ->

  @assimilate: (target, options, cb) ->
    path = require 'path'
    global.node =
      default: f = (ns, v) ->
        n = node
        t = ns.split '.'
        l = t.length - 1
        for k, i in t
          if i is l then n[k] = v
          else if typeof n[k] isnt 'object' then n[k] = {}
          n = n[k]
        return
      define: f
      require: (ns, reason='') ->
        n = node
        for k in ns.split '.'
          if n[k] is undefined then throw "Fatal: node.#{ns} is undefined. #{reason}"
          n = n[k]
        return n[k]
    require './resources'
    require 'coffee-script'
    require path.join process.cwd(), 'config.coffee'
    global.machines = require path.join process.cwd(), 'machines.coffee'
    # connect
    global.ssh = new Ssh user: target.user, pass: target.pass, host: target.host, port: target.port, cmd: options.c, ->
      global.assimilated = ->
        ssh.close()
        cb()
      node = require path.join process.cwd(), 'nodes', "#{target.host}.coffee"

  @cmd: (target, options, cb) ->
    #console.log arguments
    new Ssh user: target.user, pass: target.pass, host: target.host, port: target.port, cmd: options.c, ->
      #if err then return Logger.out host: target.host, type: 'err', err
      ssh.cmd options.cmd, {}, (err) ->
        ssh.close()
        cb()
