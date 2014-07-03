_ = require 'lodash'

module.exports =
class Borg
  constructor: ({cwd, cmd}) ->
    # build sandbox object
    @sandbox =
      cwd: cwd or process.cwd()
      log: (require './Logger').out
      die: (reason) =>
        @log type: 'err', reason
        console.trace()
        process.exit 1
        return

      define: (o) => @sandbox = _.merge @sandbox, o
      require: (ns, reason='') =>
        n = @sandbox
        for k in ns.split '.'
          if n[k] is undefined then throw "Fatal: You must @define #{ns}. #{reason}"
          n = n[k]
        return n[k]

      _Q: []
      then: (fn, args...) => @_Q.push(-> args.push @_Q.next; fn.apply null, args); @
      next: (err) => @_Q.splice 0, @_Q.length-1 if err; @_Q.shift()?.apply null, arguments
      finally: (fn, args...) => @_Q.push(-> fn.apply null, args); @next()

      fqdn: (server) -> "#{server.datacenter}-#{server.env}-#{server.instance}-#{server.machine}.#{server.tld}"
      eachServer: (cb) =>
        for datacenter, v of datacenters
          for machine, vv of networks[datacenter] when not _.contains ['_default', 'nat_networks'], machine
            for instance, vvv of vv when not _.contains ['_default'], instance
              return if false is cb datacenter: datacenter, machine: machine, instance: instance

      import: (path...) =>
        (require path.join [ @cwd ].concat path).apply @sandbox

  reloadAttributes: => (->
    # override sandbox with default attributes
    @import 'attributes', 'default'
    # load network map
    @import 'attributes', 'networks'
    # override sandbox with network attributes
    @eachServer ({ datacenter, machine, instance }) ->
      # flatten attributes enough to determine name
      attrs = {}
      if networks[datacenter]._default?
        attrs = _.clone networks[datacenter]._default
      if networks[datacenter][machine]._default?
        attrs = _.merge attrs, networks[datacenter][machine]._default
      attrs = _.merge attrs, networks[datacenter][machine][instance]
      attrs.environment ||= 'development'
      attrs.env = switch attrs.environment
        when 'development' then 'dev'
        when 'staging' then 'stage'
        when 'production' then 'prod'
        else attrs.environment
      attrs.datacenter = datacenter
      attrs.machine = machine
      attrs.instance = instance
      attrs.name = Network.fqdn attrs

      # match name
      return unless name is attrs.name or # skip unless exact match
        null isnt (new RegExp(name)).exec(attrs._name) # regex match

      # continue parsing attributes
      for i in [0, 1, 2, 3]
        if attrs.network["eth#{i}"]?.ssh_port_forward is true and attrs.network["eth#{i}"].address?
          attrs.private_ip ||= attrs.network["eth#{i}"].address if attrs.network["eth#{i}"].private is true
          attrs._ssh_nic_ip = attrs.network["eth#{i}"].address
          break # stop looping
      r = attrs
      return false # stop looping
    return r or throw "cant find machine #{name}. check: borg test list"
  ).apply @sandbox

  assimilate: ({user, key, pass, host, port, scripts, locals}) =>
    path = require 'path'
    port ||= 22

    # override sandbox with locals attributes
    @sandbox = _.merge @sandbox, locals

    # connect via ssh
    Ssh = require './Ssh'
    @ssh = new Ssh user: user, pass: pass, host: host, port: port, =>
      @assimilated = =>
        @ssh.close()
        cb()
      scripts = [ host ] unless scripts
      for script in scripts
        (require path.join @cwd, 'servers', script).apply @sandbox













# TODO: support:
# borg cmd --sudo u:p@localhost:223 -- test blah
# borg cmd --sudo u:p@localhost:223 test blah
# borg assimilate developer:tunafish@10.1.10.24:22

#class OldBorg
#  constructor: (cmd) ->
#    targets = []
#    options = {}
#    args = []
#    last_option = null
#    for arg, ii in process.argv.slice 3
#      if match = arg.match(/^(.+?)(:(.+))?@(.+?)(:(.+))?$/)
#        targets.push user: match[1], pass: match[3], host: match[4], port: match[6]
#      else
#        if arg is '--'
#          options.eol = process.argv.slice(ii+4).join ' '
#          break
#        else if arg[0] is '-'
#          options[last_option = arg.split(/^--?/)[1]] = true
#        else if last_option isnt null
#          options[last_option] += ' '+arg
#          last_option = null
#        else
#          args.push arg
#    #console.log cmd: cmd, targets: targets, options: options, args: args
#    async = require 'async2'
#    flow = new async
#    for own k, target of targets
#      ((target) ->
#        flow.parallel (next) ->
#          Borg[cmd] target, options, next
#      )(target)
#    flow.go (err, results...) ->
#      if err
#        #process.stderr.write err+"\n"
#        Logger.out 'aborted with error.'
#        process.exit 1
#      else
#        Logger.out 'all done.'
#        process.exit 0
#
#  @rekey: (target, options, cb) ->
#
#  @assimilate: (target, options, cb) ->
#    # build node object
#    global.node =
#      default: f = (ns, v) ->
#        n = node
#        t = ns.split '.'
#        l = t.length - 1
#        for k, i in t
#          if i is l then n[k] = v
#          else if typeof n[k] isnt 'object' then n[k] = {}
#          n = n[k]
#        return
#      define: f
#      require: (ns, reason='') ->
#        n = node
#        for k in ns.split '.'
#          if n[k] is undefined then throw "Fatal: node.#{ns} is undefined. #{reason}"
#          n = n[k]
#        return n[k]
#    # load network map + apply attribute defaults
#    { networks, get_instance_attrs } = global.Network = require './Network'
#    global.node.networks = networks
#    # apply target attribute defaults
#    global.node = _.merge global.node, attrs = get_instance_attrs target.host
#    # apply script attribute defaults
#    require path.join process.cwd(), 'attributes', 'default'
#
#    # connect via ssh
#    global.ssh = new Ssh user: target.user, pass: target.pass, host: target.host, port: target.port, ->
#      global.assimilated = ->
#        ssh.close()
#        cb()
#      require path.join process.cwd(), 'scripts', 'vendor', 'resources'
#      require path.join process.cwd(), 'scripts', 'first'
#      require path.join process.cwd(), 'servers', "#{target.host}.coffee"
#      require path.join process.cwd(), 'scripts', 'last'
#
#  @cmd: (target, options, cb) ->
#    #console.log arguments
#    ssh = new Ssh user: target.user, pass: target.pass, host: target.host, port: target.port, ->
#      #if err then return Logger.out host: target.host, type: 'err', err
#      ssh.cmd options.eol, {}, (err) ->
#        ssh.close()
#        cb()
