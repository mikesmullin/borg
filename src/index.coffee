path = require 'path'
fs = require 'fs'
global._ = require 'lodash'
require 'sugar'
{ Logger } = require './logger'
global.DEBUG = true
delay = (s,f) -> setTimeout f, s
crypto = require 'crypto'
jsonlint_parser = require('jsonlint').parser

module.exports =
class Borg
  constructor: (o) ->
    @cwd = o?.cwd or process.cwd()
    try
      secret_path = path.join @cwd, 'secret'
      @secret = fs.readFileSync secret_path
    catch e
      process.stderr.write "\u001b[1m\u001b[33mWARNING:\u001b[0m File `./#{path.relative @cwd, secret_path}` missing or unreadable. @encrypt()/@decrypt() will not modify input.\n\n"
      @secret = false
    try
      networks_path = path.join @cwd, 'attributes', 'networks.coffee'
      @networks = require networks_path
    catch e
      process.stderr.write "\u001b[1m\u001b[33mWARNING:\u001b[0m File `./#{path.relative @cwd, networks_path}` missing or unreadable. @networks will be empty.\n\n"
      @networks = {}
    @server = new Object

  # process
  log: -> args = arguments; (cb) -> Logger.out.apply Logger, args; cb()
  die = (reason) -> # blocking
    Logger.out type: 'err', reason
    console.trace()
    process.exit 1
  die: (reason) -> (cb) -> die reason # asynchronous

  # cryptography
  _crypt = (cmd) -> (s) ->
    return s if @secret is false
    if typeof s is 'string'
      if cmd is 'en'
        input = 'utf8'
        output = 'base64'
      else
        input = 'base64'
        output = 'utf8'
    else
      input = 'binary'
      output = 'binary'
    cipher = crypto["create#{if cmd is 'en' then 'C' else 'Dec'}ipher"] 'aes-256-cbc', @secret
    if output is 'binary'
      b = [cipher.update new Buffer(s)]
      b.push cipher.final()
      r = Buffer.concat b
    else
      r = cipher.update s, input, output
      r += cipher.final output
    return r
  encrypt: _crypt 'en'
  decrypt: _crypt 'de'
  checksum: (str, algorithm='sha256', encoding='hex') ->
    crypto
      .createHash(algorithm)
      .update(str)
      .digest(encoding)


  # async flow control
  _Q = []
  next: (err) ->
    if err
      _Q.splice 0, _Q.length-1
    _Q.shift()?.apply null, arguments
    return
  then: (fn) ->
    die 'You passed a non-function value to @then. It was: '+JSON.stringify(fn) unless typeof fn is 'function'
    _Q.push =>
      if fn.length is 0 # sync
        fn()
        @next()
      else # async
        fn @next
    return
  call: (fn, args...) -> (cb) ->
    if Array.isArray fn
      root = fn[0]
      fn = fn[0][fn[1]]
    else
      root = null
    last = args[args.length-1]
    if typeof last is 'object' and 'err' of last and typeof last.err is 'function'
      err_cb = args.pop().err
    fn.apply root, args.concat (err) ->
      if err_cb and err
        err_cb err # intercept and handle error with custom callback
        cb() # don't forward err
      else
        cb err # forward any errors
  finally: (fn) ->
    _Q.push fn # append final function as end of chain
    @next() # ignite firecracker chain-reaction
    return
  inject_flow: (fn) -> (cb) =>
    oldQ = _Q # backup
    _Q = thisQ = [] # set new empty array
    fn (warn) => # enqueue all, providing end() method
      @log(warn)(->) if warn # errors passed to end() are considered non-fatal warnings
      # if you meant for them to be fatal, you should call @die() instead of end()
      thisQ.splice 0, thisQ.length-1 # skip any remaining functions
    @finally => # kick-start
      _Q = oldQ # restore backup
      cb.apply arguments # resume chain, forwarding arguments
    return

  # attributes
  networks: null
  server: null
  define: (o) => @server = _.merge @server, o
  default: (o) => @server = _.merge o, @server

  server_name: ({ datacenter, env, type, instance, subproject, tld }) =>
    instance ||= '01'
    subproject ||= @server.subproject ||= ''
    "#{datacenter or @server.datacenter}-#{env or @server.env}-#{type}#{instance}#{subproject && '-'+subproject}.#{tld or @server.tld}"

  find_server: ({ datacenter, env, type, instance, subproject, tld, required }) =>
    locals =
      datacenter: datacenter or @server.datacenter
      env: env or @server.env
      type: type
      instance: instance
      subproject: subproject ||= @server.subproject ||= ''
      tld: tld or @server.tld
    _die = (s) ->
      die "@find_server(): no #{s} found matching "+JSON.stringify locals unless required is false
    locals.group = @_lookupGroupName locals
    unless locals.group and _group = @networks.datacenters[locals.datacenter].groups[locals.group]
      return _die 'group'
    else
      unless type
        return _group.servers
      else
        unless _type = _group.servers[locals.type]
          return _die 'type'
        else
          unless instance
            return _type.instances
          else
            unless _instance = _type.instances[locals.instance]
              return _die 'instance'
            else
              return _instance

  map_servers: ({ datacenters, envs, types, instances, subprojects, tlds, required }, map_cb) =>
    # TODO: in the future i plan to implement a crazy cross-join kind of feature
    # where you can list multiple of each param and it will join all possible combinations
    # and create a unique list of matching servers
    # and then map the values from all of them
    # but for now i only need to walk `type`
    split = (o) -> switch typeof o
      when 'string' then o.split /[, ]+/
    results = []
    for type in split types
      server = @find_server
        datacenter: datacenters
        env: envs
        type: type
        instance: instances  # TODO: support a list like '01 03 04'
        subproject: subprojects
        tlds: tlds
        required: required
      results = results.concat _.map server, map_cb
    return results

  eachServer: (each_cb) ->
    for datacenter, v of @networks.datacenters
      for group, vv of v.groups
        for type, vvv of vv.servers
          for instance, vvvv of vvv.instances
            # developer may return false to break from the loop
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
    return

  # merge/inherit network attributes down into a given instance
  _flattenInstanceAttributes: (datacenter, group, type, instance, instance_attrs={}) =>
    return _.merge {},
      @networks.global,
      _.omit @networks.datacenters[datacenter], 'groups'
      _.omit @networks.datacenters[datacenter].groups[group], 'servers'
      _.omit @networks.datacenters[datacenter].groups[group].servers[type], 'instances'
      instance_attrs
      { # these are statically defined based on position in the network object
        # hierarchy; we do not allow any crazy local overrides of these by the user
        datacenter: datacenter
        group: group
        type: type
        instance: instance
      }

  # calculate dynamic attribute values based on other attribute values
  # may be called multiple times
  _calculateAttributeValues: ({ datacenter, group, type, instance, env, tld, subproject, server }) ->
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
    server.ssh ||= {}
    server.ssh.user ||= 'ubuntu'
    server.ssh.host ||= server.public_ip or server.private_ip
    server.ssh.port ||= 22

    # transform functions into objects with sneaky javascript getters;
    # looks like a non-function but in fact yields the result of a function every time
    for key, value of server when typeof value is 'function'
      fn = Object.defineProperty server, key, get: server[key].bind server: server
      server[key] = fn

    return

  flattenNetworkAttributes: (locals) ->
    result =
      found: false
      server: {}
      possible_group: undefined

    # inject memorized servers and their attributes into network hierarchy
    memory = @remember '/'
    for fqdn, vvvv of memory when (mlocals = @parseFQDN fqdn: fqdn)
      _.merge mlocals, vvvv
      mlocals.group = @_lookupGroupName mlocals unless mlocals.group
      @_defineInstance mlocals

    @eachServer (o) =>
      # rewrite global @network object with flattened attributes accessible inside each instance
      _.merge o.server, @_flattenInstanceAttributes o.datacenter, o.group, o.type, o.instance, o.server

      # some attribute values are dynamically calculated
      @_calculateAttributeValues o

      # the current server will also have cli locals applied to it
      if typeof locals is 'object' and
        locals.datacenter is o.datacenter and
        locals.env is o.server.env and
        locals.tld is o.server.tld and
        locals.subproject is o.server.subproject # can both be null
          result.possible_group ||= o.group unless locals.group # optionally reverse-lookup server group
          if locals.type is o.type and
            locals.instance is o.instance
              result.found = true
              _.merge o.server, locals # local attributes override everything else for server

              # one particular calculated attribute comes from locals;
              # can't find a better place to do that calculation yet
              readKey = (file) -> try
                                    ''+ fs.readFileSync file
                                  catch e
                                    ''+ fs.readFileSync "#{process.env.HOME}/.ssh/#{file}"
              if o.server.provider is 'aws'
                o.server.ssh.key ||= readKey o.server.aws_key
              else if o.server.ssh.key_file
                o.server.ssh.key ||= readKey o.server.ssh.key_file

              result.server = o.server

    return result

  parseFQDN: (locals) ->
    if null isnt matches = locals.fqdn.match /^(test-)?([a-z]{2,3}-[a-z]{2,3})-([a-z]{1,5})-([a-z-]+)(\d{2,4})(?:-([a-z]+))?(?:\.(\w+\.[a-z]{2,3}))$/i
      [nil, nil, locals.datacenter, locals.env, locals.type, locals.instance, locals.subproject, locals.tld] = matches
      return locals
    return false

  _defineInstance: (locals) ->
    @networks.datacenters[locals.datacenter].groups[locals.group].servers[locals.type] ||= {}
    @networks.datacenters[locals.datacenter].groups[locals.group].servers[locals.type].instances ||= {}
    server = @networks.datacenters[locals.datacenter].groups[locals.group].servers[locals.type].instances[locals.instance] ||= {}
    _.merge server, locals # local attributes override everything else for server

  _lookupGroupName: (locals) ->
    # NOTICE: must flatten hierarchy before calling this function
    # NOTICE: network-defined type and instance help, but aren't required
    for group, v of @networks.datacenters[locals.datacenter].groups
      if v.servers?
        # dc, env, type, instance defined == best match
        if v.servers[locals.type]?.instances?[locals.instance]?.env is locals.env
          return group
        else
          # dc, env, type defined without instance == good match
          # dc, env defined without type or instance == poor match (ask human to approve)
          # NOTICE: here we project what the env WOULD be if type and instance WERE defined
          flattened_attributes = @_flattenInstanceAttributes locals.datacenter, group, locals.type, locals.instance, {}
          if flattened_attributes.env is locals.env
            return group

    console.trace()
    throw "unable to find any group matching locals #{JSON.stringify locals}"

  # compile all attributes into a single @server object hierarchy
  getServerObject: (locals, cb) ->
    if process.options.locals
      _.merge locals, process.options.locals
      if process.options.save
        # memorize these changes for future references
        console.log "Will remember instance locals:\n"+JSON.stringify process.options.locals
        @remember "/#{locals.fqdn}", process.options.locals

    # helpful for debugging
    scrubbed_locals = _.cloneDeep locals
    scrubbed_locals.ssh.pass = 'SCRUBBED' if scrubbed_locals.ssh?.pass
    scrubbed_locals.ssh.key = 'SCRUBBED' if scrubbed_locals.ssh?.key
    #console.log "Interpreted locals:\n"+JSON.stringify scrubbed_locals

    # parse fqdn into name parts
    if locals.fqdn
      unless @parseFQDN locals
        die "unrecognized fqdn format: #{locals.fqdn}. should be {datacenter}-{env}-{type}{instance}-{subproject}{tld}"
    else unless locals.datacenter and locals.env and locals.type and locals.instance and locals.tld
      die 'missing required locals.fqdn or all of locals: datacenter, env, type, instance, tld. cannot continue.'

    # server object begins with network attributes from matching fqdn
    { found, server, possible_group } = @flattenNetworkAttributes locals
    if found
      return cb server
    else
      die "Unable to locate server within network attributes." unless possible_group # TODO: could define an automatic group name, but meh.
      console.log """
      \nWARNING! Instance "#{locals.type}#{locals.instance}" is undefined in network.coffee and memory.json.
      A NEW instance will be appended to memory.json based upon attributes
      matching dc: "#{locals.datacenter}", group: "#{possible_group}", env: "#{locals.env}", type: "#{locals.type}"
      """
      @cliConfirm "Proceed?", =>
        locals.group = possible_group
        @remember "/#{locals.fqdn}/group", locals.group
        @_defineInstance locals
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
    process.stdin.on 'data', (chunk) ->
      if chunk isnt null
        process.stdin.removeAllListeners 'data'
        process.stdin.pause()
        return fail_cb() if (''+chunk).toLowerCase() isnt "y\n"
        cb()
    process.stdin.resume()

  # scripts
  import: (paths...) ->
    p = path.join.apply null, paths
    Logger.out "importing #{p}..."
    try
      stats = fs.statSync p
      if stats.isDirectory()
        @importCwd = p
    catch err
      if err?.code is 'ENOENT'
        @importCwd = path.dirname p
      else
        die err
    finally
      @then @log "entering #{p}..."
      (require p).apply @
      @then @log "exiting #{p}..."

  # save instance details to disk for future reference
  remember: (xpath, value) ->
    # load
    memory_file = path.join process.cwd(), 'attributes', 'memory.json'
    try
      delete require.cache[require.resolve memory_file] # invalidate cache
      memory = require memory_file
    catch e
      # try to tell user why the JSON is unparseable.
      jsonlint_parser.parse(fs.readFileSync(memory_file).toString())
      console.log e
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
            if typeof pointer[key] is 'object' and typeof value is 'object'
              pointer[key] = _.merge {}, pointer[key], value # merge existing objects
            else
              pointer[key] = value # otherwise override
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
    cb null


  create: (locals, cb) ->
    @getServerObject locals, (@server) =>
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
              locals.public_ip = instance.publicIpAddress
              locals.private_ip = instance.privateIpAddress

              ms = 60*1000*1
              console.log "waiting #{ms}ms extra for aws to REALLY be ready..."
              delay ms, next # needs time to initialize or ssh connect and cmds will hang indefinitely

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
    # load server attributes for named host
    @getServerObject locals, (@server) =>
      #console.log "@server object attributes before scripts:\n"+ JSON.stringify server, null, 2

      # the most basic resources come from a vendor repository
      @import @cwd, 'scripts', 'vendor', 'resources'

      # begin chaining script execution callbacks
      #@server.scripts ||= [ 'servers/'+@server.ssh.host ]
      @server.scripts ||= []

      # include scripts attributes for matches in scripts/servers/*.coffee
      scripts = fs.readdirSync path.join @cwd, 'scripts', 'servers'
      for script in scripts when script isnt 'blank.coffee' and null isnt script.match /\.coffee$/
        script_path = path.join @cwd, 'scripts', 'servers', script
        o = require script_path
        die "The `target: ->` callback function is missing from #{script_path}. Cannot continue." unless typeof o.target is 'function'
        if o.target.apply @
          @server.scripts.push path.join 'scripts', 'servers', script
      unless @server.scripts.length
        blank_path = path.join 'scripts', 'servers', 'blank.coffee'
        try
          fs.statSync blank_path
          @server.scripts.push blank_path
        catch e
          console.log "error: "+e
          # do nothing

      for script in @server.scripts
        script_path = path.join @cwd, script
        o = require script_path
        die "The `assimilate: ->` callback function is missing from #{script_path}. Cannot continue." unless typeof o.assimilate is 'function'
        o.assimilate.apply @

      console.log "@server object attributes after scripts:\n"+ JSON.stringify @server, null, 2

      # connect via ssh
      Ssh = require './ssh'
      @ssh = new Ssh @server.ssh, (err) =>
        die err if err
        # finish and execute chain
        @finally (err) =>
          die err if err
          @ssh.close()
          delay 100, =>
            Logger.out type: 'info', "Assimilation complete."
            console.log "#{@server.ssh.host} #{@server.fqdn}\n"
            cb null


  assemble: (locals, cb) ->
    # people like to customize the ssh port for security reasons.
    # however, a brand new vm is usually listening on the default port.
    # therefore we ignore user customizations and presume to use port tcp/22 with assemble
    # unless the user specifies otherwise via cli --locals=ssh:port:
    locals.ssh ||= {}
    locals.ssh.port ||= 22
    locals.permitReboot = true unless locals.permitReboot = false
    @create locals, =>
      @assimilate locals, cb
        # TODO: also run checkup


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
