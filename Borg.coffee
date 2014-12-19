path = require 'path'
fs = require 'fs'
_ = require 'lodash'
require 'sugar'
Logger = require './Logger'
global.DEBUG = true
{ delay } = require './util'

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
    @networks = require path.join @cwd, 'attributes', 'networks'
    @server = new Object

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

  server_name: ({ datacenter, env, type, instance, subproject, tld }) =>
    instance ||= '01'
    subproject ||= @server.subproject ||= ''
    "#{datacenter or @server.datacenter}-#{env or @server.env}-#{type}#{instance}#{subproject && '-'+subproject}.#{tld or @server.tld}"

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

  flattenNetworkAttributes: (locals=null) ->
    _server = {}
    found = false
    possible_group = undefined

    # inject memorized servers and their attributes into network hierarchy
    memory = @remember '/'
    for fqdn, vvvv of memory when (_locals = @parseFQDN fqdn: fqdn)
      _.merge _locals, vvvv
      @defineNetworkServer _locals

    # traverse and expand network hierarchy
    @eachServer ({ datacenter, group, type, instance, env, tld, subproject, server }) =>
      d = _.merge {},
        @networks.global,
        _.omit @networks.datacenters[datacenter], 'groups'
        _.omit @networks.datacenters[datacenter].groups[group], 'servers'
        _.omit @networks.datacenters[datacenter].groups[group].servers[type], 'instances'
        server
      _.merge server, d

      # plus a few implicitly calculated attributes
      server.datacenter ||= datacenter
      server.group ||= group
      server.type ||= type
      server.instance ||= instance
      server.environment ||= switch server.env
        when 'dev' then 'development'
        when 'stage' then 'staging'
        when 'prod' then 'production'
        else server.env
      server.fqdn ||= "#{server.datacenter}-#{server.env}-#{server.type}#{server.instance}#{if server.subproject then '-'+server.subproject else ''}.#{server.tld}"
      server.hostname ||= "#{server.datacenter}-#{server.env}-#{server.type}#{server.instance}#{if server.subproject then '-'+server.subproject else ''}"
      for own dev, adapter of server.network when adapter.private and adapter.address
        server.private_ip ||= adapter.address
        break

      # expand function values
      for key, value of server when typeof value is 'function'
        server[key] = value.apply server: server

      # determine if current server
      if locals isnt null and
        locals.datacenter is datacenter and
        locals.env is server.env and
        locals.tld is server.tld and
        locals.subproject is server.subproject # can both be null
          possible_group ||= group unless locals.group # optionally reverse-lookup server group
          if locals.type is type and
            locals.instance is instance
              found = true
              _.merge server, locals # local attributes override everything else for server
              _server = server
    return found: found, server: _server, possible_group: possible_group

  parseFQDN: (locals) ->
    if null isnt matches = locals.fqdn.match /^(test-)?([a-z]{2,3}-[a-z]{2,3})-([a-z]{1,5})-([a-z-]+)(\d{2,4})(?:-([a-z]+))?(?:\.(\w+\.[a-z]{2,3}))$/i
      [nil, nil, locals.datacenter, locals.env, locals.type, locals.instance, locals.subproject, locals.tld] = matches
      return locals
    return false

  defineNetworkServer: (locals) ->
    @networks.datacenters[locals.datacenter].groups[locals.group].servers[locals.type] ||= {}
    @networks.datacenters[locals.datacenter].groups[locals.group].servers[locals.type].instances ||= {}
    server = @networks.datacenters[locals.datacenter].groups[locals.group].servers[locals.type].instances[locals.instance] ||= {}
    _.merge server, locals # local attributes override everything else for server
    return server

  # compile all attributes into a single @server object hierarchy
  getServerObject: (locals, cb) ->
    # allow users to pass CSON via --locals cli argument
    if process.options.locals
      CoffeeScript = require 'coffee-script'
      data = eval CoffeeScript.compile process.options.locals, bare: true
      _.merge locals, data
      if process.options.save
        # memorize these changes for future references
        console.log "Will remember instance locals:\n"+JSON.stringify data
        @remember "/#{locals.fqdn}", data

    # helpful for debugging
    scrubbed_locals = _.cloneDeep locals
    scrubbed_locals.ssh.pass = 'SCRUBBED' if scrubbed_locals.ssh?.pass
    scrubbed_locals.ssh.key = 'SCRUBBED' if scrubbed_locals.ssh?.key
    console.log "Interpreted locals:\n"+JSON.stringify scrubbed_locals

    # parse fqdn into name parts
    if locals.fqdn
      unless @parseFQDN locals
        @die "unrecognized fqdn format: #{locals.fqdn}. should be {datacenter}-{env}-{type}{instance}-{subproject}{tld}"
    else unless locals.datacenter and locals.env and locals.type and locals.instance and locals.tld
      @die 'missing required locals.fqdn or all of locals: datacenter, env, type, instance, tld. cannot continue.'

    # server object begins with network attributes from matching fqdn
    { found,  server, possible_group } = @flattenNetworkAttributes locals
    if found
      return cb server
    else
      @die "Unable to locate server within network attributes." unless possible_group # TODO: could define an automatic group name, but meh.
      console.log "WARNING! Server was not defined in network attributes. Will add it under '#{possible_group}' group."
      @cliConfirm "Proceed?", =>
        locals.group = possible_group
        @defineNetworkServer locals
        { server } = @flattenNetworkAttributes locals # again, now that our server is defined
        return cb server

  cliConfirm: (question, cb) ->
    fail_cb = ->
      console.log "Aborted.\n"
      process.exit 1
    process.stdout.write "\n#{question} [y/N] "
    unless USING_CLI
      process.stderr.write "Error: tty stdin required to answer, but not using cli.\n"
      return fail_cb()
    process.stdin.on 'readable', ->
      chunk = process.stdin.read()
      if chunk isnt null
        process.stdin.pause()
        process.stdin.removeAllListeners 'readable'
        return fail_cb() if (''+chunk).toLowerCase() isnt "y\n"
        cb()
    process.stdin.resume()

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

  # save instance details to disk for future reference
  remember: (xpath, value) ->
    # load
    memory_file = path.join process.cwd(), 'attributes', 'memory.json'
    delete require.cache[require.resolve memory_file] # invalidate cache
    memory = require memory_file
    # evaluate path
    pointer = memory
    return pointer if xpath is '/' and value is undefined
    parts = xpath.split '/'
    for i in [0...parts.length]
      key = parts[i]
      continue if key is '' # skip empty key names so / can be used as root
      if i is parts.length-1
        # operate
        if value is undefined # read
          return pointer[key]
        else
          if value is null # delete
            delete pointer[key]
          else # write
            pointer[key] = _.merge {}, pointer[key], value
          fs.writeFileSync memory_file, JSON.stringify memory, null, 2
          return
      else
        pointer[key] ||= {} # make new keys recursively
        pointer = pointer[key] # advance pointer one level deeper


  ## api / cli
  list: (locals, cb) ->
    rx = new RegExp process.argv[4], 'g'
    @flattenNetworkAttributes()
    last_group = undefined
    count = 0
    @eachServer ({ server }) ->
      if null isnt server.fqdn.match(rx) and null is server.fqdn.match /^test-/
        count++
        if server.group isnt last_group
          console.log "\n# #{server.datacenter} #{server.group}"
          last_group = server.group
        console.log "#{((server.public_ip or server.private_ip or '#')+'            ').substr 0, 16}#{server.fqdn}"
    process.stderr.write "\n#{count} network server definition(s) found.\n\n"

  create: (locals, cb) ->
    @getServerObject locals, (@server) =>
      @remember "/#{locals.fqdn}/group", locals.group
      #console.log "Network attributes:\n"+ JSON.stringify @networks, null, 2

      provision = =>
        console.log "asking #{@server.provider} to create..."
        switch @server.provider
          when 'aws'
            Aws = (require './cloud/aws')(console.log)
            Aws.createInstance @server.fqdn, @server, ((id) =>
              console.log "got instance_id #{id}..."
              @remember "/#{locals.fqdn}/aws_instance_id", locals.aws_instance_id = id
            ), (instance) ->
              ms = 60*1000*1
              console.log "waiting #{ms}ms extra for aws to REALLY be ready..."
              delay ms, -> # needs time to initialize or ssh connect and cmds will hang indefinitely
                locals.public_ip = instance.publicIpAddress
                locals.private_ip = instance.privateIpAddress
                next()

      next = =>
        @remember "/#{locals.fqdn}/private_ip", locals.private_ip
        @remember "/#{locals.fqdn}/public_ip", locals.public_ip

        # build remaining locals to match would-be calculated values
        # TODO: possibly call createServerObject() again here
        locals.network ||= {}
        locals.network.eth1 ||= {}
        locals.network.eth1.address = locals.private_ip
        locals.ssh ||= {}
        locals.ssh.host = locals.public_ip or locals.private_ip

        console.log "Created new host:\n#{locals.ssh.host} #{locals.fqdn}\n"
        cb()

      provision()


  assimilate: (locals, cb) ->
    locals.ssh ||= {}
    locals.ssh.user ||= 'ubuntu'

    # load server attributes for named host
    @getServerObject locals, (@server) =>
      @server.ssh.host ||= @server.public_ip or @server.private_ip
      readKey = (file) -> ''+ fs.readFileSync "#{process.env.HOME}/.ssh/#{file}"
      if @server.provider is 'aws'
        @server.ssh.key ||= readKey @server.aws_key
      else if @server.ssh.key_file
        @server.ssh.key ||= readKey @server.ssh.key_file

      console.log "Server attributes before scripts:\n"+ JSON.stringify server, null, 2

      # the most basic resources come from a vendor repository
      @import @cwd, 'scripts', 'vendor', 'resources'

      # begin chaining script execution callbacks
      #@server.scripts ||= [ 'servers/'+@server.ssh.host ]
      @server.scripts ||= []

      # include scripts attributes for matches in scripts/servers/*.coffee
      scripts = fs.readdirSync path.join @cwd, 'scripts', 'servers'
      for script in scripts when script isnt 'blank.coffee' and null isnt script.match /\.coffee$/
        if true is (require path.join @cwd, 'scripts', 'servers', script).target.apply @
          @server.scripts.push path.join 'scripts', 'servers', script
      unless @server.scripts.length
        @server.scripts.push path.join 'scripts', 'servers', 'blank'

      for script in @server.scripts
        (require path.join @cwd, script).assimilate.apply @

      console.log "Server attributes after scripts:\n"+ JSON.stringify @server, null, 2

      # connect via ssh
      Ssh = require './Ssh'
      @ssh = new Ssh @server.ssh, (err) =>
        return cb err if err
        # finish and execute chain
        @finally (err) =>
          return cb err if err
          @ssh.close()
          delay 100, =>
            console.log "Assimilated #{@server.fqdn or @server.ssh.host}."
            cb null


  assemble: (locals, cb) ->
    @create locals, =>
      @assimilate locals, cb


  destroy: (locals, cb) ->
    @getServerObject locals, (@server) =>
      terminate = =>
        switch @server.provider
          when 'aws'
            Aws = (require './cloud/aws')(console.log)
            Aws.destroyInstance @server, next

      next = =>
        @remember "/#{locals.fqdn}", null # forget server
        console.log "Destroyed #{locals.fqdn}."
        cb()

      console.log "asking #{@server.fqdn} (#{@server.public_ip or @server.private_ip or ''}) to terminate..."
      if USING_CLI
        @cliConfirm "Proceed?", terminate
      else
        terminate()




























  # TODO: test this and make it work again
  #cmd: (target, options, cb) ->
  #  console.log arguments
  #  # TODO: reimplement regex matching when we want to match on more than one hostname
  #  ssh = new Ssh user: target.user, pass: target.pass, host: target.host, port: target.port, ->
  #    if err then return Logger.out host: target.host, type: 'err', err
  #    ssh.cmd options.eol, {}, (err) ->
  #      ssh.close()
  #      cb()

  # TODO: support the following command syntax:
  #   borg cmd --sudo u:p@localhost:223 -- test blah
  #   borg cmd --sudo u:p@localhost:223 test blah
  #   borg assimilate developer:tunafish@10.1.10.24:22

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
