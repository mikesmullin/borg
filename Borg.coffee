path = require 'path'
fs = require 'fs'
_ = require 'lodash'
require 'sugar'
Logger = require './Logger'
global.DEBUG = true
delay = (s,f) -> setTimeout f, s

module.exports =
class Borg
  # process
  log: -> Logger.out.apply Logger, arguments
  die: (reason) ->
    @log type: 'err', reason
    console.trace()
    process.exit 1
    return

  constructor: (o) ->
    @cwd = o?.cwd or process.cwd()
    @networks = {}
    @server = {}

  # async flow control
  _Q: []
  next: (err) => @_Q.splice 0, @_Q.length-1 if err; @_Q.shift()?.apply null, arguments
  then: (fn, args...) ->
    @die 'You passed a non-function value to @then. It was: '+JSON.stringify(fn)+' with args: '+JSON.stringify(args) unless typeof fn is 'function'
    @_Q.push(=> args.push @next; fn.apply null, args); @
  finally: (fn) => @_Q.push fn; @next()
  sub: (fn, cb) =>
    oldQ = @_Q
    @_Q = []
    fn (warn) =>
      @log warn if warn # errors passed to end() are considered non-fatal warnings
      # if you meant for them to be fatal, you shuold call @die() instead of end()
      @_Q.splice 0, @_Q.length-1 # skip any remaining functions
      @_Q.shift()?.apply null
    @finally (err) =>
      @die err if err
      @_Q = oldQ
      cb()

  # attributes
  networks: null
  server: null
  define: (o) => @server = _.merge @server, o
  default: (o) => @server = _.merge o, @server

  eachServer: (each_cb) ->
    for datacenter, v of @networks.datacenters
      for group, vv of v.groups
        for type, vvv of vv.servers
          for instance, vvvv of vvv.instances
            return false if false is each_cb({
              datacenter: datacenter
              group: group
              type: type
              instance: instance
              env: vvvv.env
              tld: vvvv.tld
              subproject: vvvv.subproject
              server: vvvv
            })


  # compile all attributes into a single @server object hierarchy
  getServerObject: (locals) ->
    locals ||= {}
    if locals.fqdn
      if null isnt matches = locals.fqdn.match /^([a-z]{2,3}-[a-z]{2})-([a-z]{1,5})-([a-z-]+)(\d{2,4})(-([a-z]+))?(\.(\w+\.[a-z]{2,3}))$/i
        [nil, locals.datacenter, locals.env, locals.type, locals.instance, nil, locals.subproject, nil, locals.tld] = matches
      else
        @die "unrecognized fqdn format: #{locals.fqdn}. should be {datacenter}-{env}-{type}{instance}-{subproject}{tld}"
    else if locals.datacenter and locals.env and locals.type and locals.instance and locals.tld
      locals.fqdn = "#{locals.datacenter}-#{locals.env}-#{locals.type}#{locals.instance}.#{locals.tld}"
    else
      @die "locals.fqdn is required. cannot continue."

    # helpful for debugging
    scrubbed_locals = _.cloneDeep locals
    scrubbed_locals.ssh.pass = 'SCRUBBED' if scrubbed_locals.ssh?.pass
    scrubbed_locals.ssh.key = 'SCRUBBED' if scrubbed_locals.ssh?.key
    console.log "You passed:\n"+JSON.stringify scrubbed_locals

    # load network attributes
    @networks = require path.join @cwd, 'attributes', 'networks'

    # flatten network attributes
    _server = {} # NOTICE: server object begins with network attributes matching fqdn
    found = false
    possible_group = undefined
    flattenNetworkAttributes = =>
      @eachServer ({ datacenter, group, type, instance, env, tld, subproject, server }) =>
        _.merge server,
          @networks.global,
          _.omit @networks.datacenters[datacenter], 'groups'
          _.omit @networks.datacenters[datacenter].groups[group], 'servers'
          _.omit @networks.datacenters[datacenter].groups[group].servers[type], 'instances'
          server

        # plus a few implicitly calculated attributes
        server.datacenter ||= datacenter
        server.group ||= group
        server.type ||= type
        server.instance ||= instance
        server.environment = switch server.env
          when 'dev' then 'development'
          when 'stage' then 'staging'
          when 'prod' then 'production'
          else server.env
        server.fqdn = "#{server.datacenter}-#{server.env}-#{server.type}#{server.instance}#{if server.subproject then '-'+server.subproject else ''}.#{server.tld}"
        server.hostname = "#{server.datacenter}-#{server.env}-#{server.type}#{server.instance}#{if server.subproject then '-'+server.subproject else ''}"
        for own dev, adapter of server.network when adapter.private
          server.private_ip = adapter.address
          break

        # apply details remembered
        _.merge server, @remember server.fqdn

        # expand function values
        for key, value of server when typeof value is 'function'
          server[key] = value.apply server: server

        # determine if current server
        if locals.datacenter is datacenter and
          locals.env is server.env and
          locals.tld is server.tld and
          locals.subproject is server.subproject # can both be null
            possible_group ||= group unless locals.group # optionally reverse-lookup server group
            if locals.type is type and
              locals.instance is instance
                found = true
                _server = server

    flattenNetworkAttributes()
    unless found
      @die "Unable to locate server within network attributes." unless possible_group # TODO: could define an automatic group name, but meh.
      console.log "WARNING! Server was not defined in network attributes. Assuming you meant to add it under '#{possible_group}' group."
      @networks.datacenters[locals.datacenter].groups[possible_group].servers[locals.type] ||= {}
      @networks.datacenters[locals.datacenter].groups[possible_group].servers[locals.type].instances ||= {}
      @networks.datacenters[locals.datacenter].groups[possible_group].servers[locals.type].instances[locals.instance] = {} # destructive, but shouldn't exist here
      flattenNetworkAttributes() # again, now that our server is defined
      _server = @networks.datacenters[locals.datacenter].groups[possible_group].servers[locals.type].instances[locals.instance]

    #console.log "Network attributes:\n"+ JSON.stringify @networks, null, 2

    # local attributes override everything else for current server
    _.merge _server, locals

    console.log "Server attributes before scripts:\n"+ JSON.stringify _server, null, 2

    return _server

  # scripts
  import: (paths...) ->
    p = path.join.apply null, paths
    @log "importing #{p}..."
    try
      stats = fs.statSync p
      if stats.isDirectory()
        @importCwd = p
    catch err
      if err?.code is 'ENOENT'
        @importCwd = path.dirname p
      else
        @die err
    finally
      (require p).apply @

  remember: (xpath, value=undefined) ->
    # load
    memory_file = path.join process.cwd(), 'attributes', 'memory.json'
    delete require.cache[require.resolve memory_file] # invalidate cache
    memory = require memory_file
    # evaluate path
    pointer = memory
    parts = xpath.split '/'
    for i in [0...parts.length]
      key = parts[i]
      continue if key is '' # skip empty key names so / can be used as root
      if i is parts.length-1
        # operate
        if value is undefined # read
          return pointer[key]
        else # write
          pointer[key] = value
          fs.writeFileSync memory_file, JSON.stringify memory, null, 2
          return
      else
        pointer[key] ||= {} # make new keys recursively
        pointer = pointer[key] # advance pointer one level deeper


  ## api / cli
  create: (locals, cb) ->
    @server = @getServerObject locals

    provision = =>
      console.log 'beginning provision'
      switch @server.provider
        when 'aws'
          Aws = (require './cloud/aws')(console.log)
          Aws.createInstance @server.fqdn, @server, ((id) ->
            console.log "procuring instance_id #{id}..."
          ), (instance) -> delay 60*1000*1, -> # needs time to initialize or ssh connect and cmds will hang indefinitely
            locals.public_ip = instance.publicIpAddress
            locals.private_ip = instance.privateIpAddress
            next()

    next = =>
      # save a few instance details to disk for future reference
      @remember "/#{locals.fqdn}/private_ip", locals.private_ip
      @remember "/#{locals.fqdn}/public_ip", locals.public_ip

      # build remaining locals to match would-be calculated values
      # TODO: possibly call createServerObject() again here
      locals.network ||= {}
      locals.network.eth1 ||= {}
      locals.network.eth1.address = locals.private_ip
      locals.ssh ||= {}
      locals.ssh.host = locals.public_ip or locals.private_ip

      # assimilate the new machine
      console.log "assimilating #{locals.ssh.host}..."
      @assimilate locals, cb

    provision()


  assimilate: (locals, cb) ->
    locals.ssh ||= {}
    locals.ssh.port ||= 22

    # load server attributes for named host
    @server = @getServerObject locals

    # connect via ssh
    Ssh = require './Ssh'
    @ssh = new Ssh locals.ssh, (err) =>
      return cb err if err
      @finally (err) =>
        @die err if err
        @ssh.close()
        setTimeout (-> cb null), 100

    # all resources come from a separate vendor repository
    @import @cwd, 'scripts', 'vendor', 'resources'

    # begin chaining script execution callbacks
    #locals.scripts ||= [ 'servers/'+locals.ssh.host ]
    locals.scripts ||= []

    # find matching role(s)
    roles = fs.readdirSync path.join @cwd, 'scripts', 'roles'
    for role in roles
      rx = role.replace(/\.coffee$/, '').replace(/\./g, '\\.').replace(/_/g, '.+')
      console.log rx: rx, fqdn: locals.fqdn
      unless null is locals.fqdn.match rx
        locals.scripts.push path.join 'roles', role
        break # for now, only take the first match

    for script in locals.scripts
      @import @cwd, 'scripts', script

    # finish and execute chain
    console.log "Server attributes after scripts:\n"+ JSON.stringify @server, null, 2

  assemble: (locals, cb) ->
    @provision locals, =>
      @assimilate locals, cb

  # TODO: test this and make it work again
  cmd: (target, options, cb) ->
    console.log arguments
    # TODO: reimplement regex matching when we want to match on more than one hostname
    ssh = new Ssh user: target.user, pass: target.pass, host: target.host, port: target.port, ->
      if err then return Logger.out host: target.host, type: 'err', err
      ssh.cmd options.eol, {}, (err) ->
        ssh.close()
        cb()







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
