path = require 'path'
fs = require 'fs'
_ = require 'lodash'
require 'sugar'
Logger = require './Logger'

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
  networks: {}
  server: {}
  define: (o) => @server = _.merge @server, o
  default: (o) => @server = _.merge o, @server

  # compile all attributes into a single @server object hierarchy
  getServerObject: (locals) ->
    # helpful for debugging
    scrubbed_locals = _.cloneDeep locals
    scrubbed_locals.ssh.pass = 'SCRUBBED' if scrubbed_locals.ssh?.pass
    scrubbed_locals.ssh.key = 'SCRUBBED' if scrubbed_locals.ssh?.key
    console.log "You passed: "+JSON.stringify scrubbed_locals

    # load network attributes
    @networks = require path.join @cwd, 'attributes', 'networks'
    # flatten network attributes
    for datacenter, v of @networks.datacenters
      for group, vv of v.groups
        for server, vvv of vv.servers
          for instance, vvvv of vvv.instances
            _.merge vvvv,
              @networks.global,
              _.omit v, 'groups'
              _.omit vv, 'servers'
              _.omit vvv, 'instances'
              vvvv
    #console.log "Network attributes: "+ JSON.stringify @networks, null, 2

    server = {}
    # find server matching pattern, override server attributes with matching network instance attributes
    _.merge server, (findServer = ({datacenter, env, type, instance, subproject, tld}) =>
      if v = @networks.datacenters[datacenter]
        for nil, vv of v.groups when (vvvv = vv.servers[type]?.instances[instance]) and
          vvvv.env is env and
          vvvv.tld is tld and
          vvvv.subproject is subproject # can both be null
            return vvvv
    )(locals)

    # apply local attributes
    _.merge server, locals

    # plus a few implicitly calculated attributes
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

    # local attributes override everything else
    _.merge server, locals

    console.log "Server attributes: "+ JSON.stringify server, null, 2
    return server

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



  ## api / cli
  create: (locals, cb) ->
    locals ||= {}
    if locals.fqdn
      if null isnt matches = locals.fqdn.match /^([a-z]{2,3}-[a-z]{2})-([a-z]{1,5})-([a-z-]+)(\d{2,4})(-([a-z]+))?(\.(\w+\.[a-z]{2,3}))$/i
        [nil, locals.datacenter, locals.env, locals.type, locals.instance, nil, locals.subproject, nil, locals.tld] = matches
      else
        @die "unrecognized fqdn format: #{locals.fqdn}. should be {datacenter}-{env}-{type}{instance}-{subproject}{tld}"
    else if locals.datacenter and locals.env and locals.type and locals.instance and locals.tld
      locals.fqdn = "#{locals.datacenter}-#{locals.env}-#{locals.type}#{locals.instance}.#{locals.tld}"
    else
      @die "locals.fqdn is required by create(). cannot continue."

    @server = @getServerObject locals
    process.exit 1

    switch @server.provider
      when 'aws'
        Aws = require './aws'
        Aws.createInstance locals.fqdn, job, ((instanceId) ->
          # create instance with 'preparing' status
          locals.status = 'procuring'
          rememberInstance
            instance_id: instanceId
            locals: locals
            ->
        ), (instance) -> delay 60*1000*2, -> # needs time to initialize or ssh connect and cmds will hang indefinitely
          # save instance details for later deletion
          locals.public_ip = instance.publicIpAddress
          locals.private_ip = instance.privateIpAddress
          locals.network ||= {}
          locals.network.eth1 ||= {}
          locals.network.eth1.address = instance.privateIpAddress
          locals.status = 'assimilating'
          rememberInstance
            instance_id: instance.instanceId
            locals: locals
            ->
              # assimilate the new machine
              locals.ssh ||= {}
              locals.ssh.host = instance.publicIpAddress or instance.privateIpAddress
              callBorg locals, (err) ->
                if err
                  locals.status = 'error'
                else
                  locals.status = 'running'
                rememberInstance instance_id: instance.instanceId, locals: locals, ->
                  done !err

  assimilate: (locals, cb) ->
    locals.ssh ||= {}
    locals.ssh.port ||= 22

    # load server attributes for named host
    @reloadAttributes locals.ssh.host, locals

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
    locals.scripts ||= [ 'servers/'+locals.ssh.host ]
    for script in locals.scripts
      @import @cwd, 'scripts', script

    # finish and execute chain
    console.log 'server:'+ JSON.stringify @server, null, 2

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
