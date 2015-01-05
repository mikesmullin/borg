process.stdin.setEncoding 'utf8'
require 'sugar'
_     = require 'lodash'
path  = require 'path'
async = require 'async2'
{ delay } = require '../util'

module.exports = (borg) ->
  cloud_provider = 'aws' # hard-coded for now
  rx = new RegExp process.args[2], 'g'
  borg.flattenNetworkAttributes()

  confirmSelection = ({ hide_ips, test_prefix, require_test_match, action }, cb) =>
    borg.die "host_or_regex required." unless process.args[2]
    servers = []
    borg.eachServer ({ server }) ->
      if null isnt server.fqdn.match(rx) and
        (not require_test_match or server.fqdn.match /^test-/)
          servers.push server
    if servers.length
      console.log "These existing network server definitions will be #{action or 'used'}:\n"
      for server in servers
        console.log "  #{if hide_ips then '' else server.public_ip or server.private_ip or '#'} #{server.fqdn}"
      borg.cliConfirm "Proceed?", -> cb servers
    else if require_test_match
      process.stderr.write "\n0 existing network server definition(s) found.#{if rx then ' FQDN RegEx: '+rx else ''}\n\n"
    else
      console.log "Cannot continue; not implemented to add new network server definitions in test mode, yet."
      process.exit 1
      #console.log "Assuming this is a new network server definition."
      #cb [ fqdn: process.args[2] ]

  list = =>
      count = 0
      process.stdout.write "\n"
      borg.eachServer ({ server }) ->
        if null isnt server.fqdn.match(rx) and null isnt server.fqdn.match /^test-/
          count++
          console.log "#{((server.public_ip or server.private_ip or '#')+'            ').substr 0, 16}#{server.fqdn}"
      process.stderr.write "\n#{count} existing network server definition(s) found.#{if rx then ' FQDN RegEx: '+rx else ''}\n\n"

  create = (locals, cb) =>
    confirmSelection action: 'duplicated with test- prefix', (servers) => for server in servers
      flow = new async
      for server in servers
        if null isnt server.fqdn.match /^test-/
          console.log "NOTICE: Won't make two of the same test server. Reuse or destroy the existing instance."
          continue
        ((server) ->
          # TODO introduce parallel option, with intercepted + colorized log output
          flow.serial (next) ->
            locals ||= {}
            locals.fqdn ||= if server.fqdn.match /^test-/ then server.fqdn else 'test-'+server.fqdn
            borg.create locals, next
        )(server)
      flow.go ->
        cb()

  assimilate = (locals, cb) =>
    # NOTICE: can't test assimilate instances that we don't have memory of
    confirmSelection require_test_match: true, action: 're-assimilated', (servers) => for server in servers
      flow = new async
      for server in servers
        ((server) ->
          # TODO introduce parallel option, with intercepted + colorized log output
          flow.serial (next) ->
            locals ||= {}
            locals.fqdn ||= if server.fqdn.match /^test-/ then server.fqdn else 'test-'+server.fqdn
            borg.assimilate locals, next
        )(server)
      flow.go ->
        cb()

  switch process.args[1]
    # TODO: call real Borg functions for this, passing test- prefix as a locals option
    when 'list' then list()
    when 'create' then create {}, => process.exit 0
    when 'assimilate' then assimilate {}, => process.exit 0
    when 'assemble'
      locals = {}
      locals.ssh ||= {}
      locals.ssh.port ||= 22
      create locals, =>
        assimilate locals, =>
          # TODO: also run checkup
          process.exit 0

    when 'checkup'
      # TODO: run mocha-based test suite
      return

    when 'login'
      # TODO: spawn new terminal with ssh, or cssh if multiple hosts matched
      #child_process.spawn 'ssh', [], env: process.env, stdio: 'passthru'
      console.log "Not implemented, yet."
      return

    when 'destroy'
      # NOTICE: can't test assimilate instances that we don't have memory of
      confirmSelection require_test_match: true, action: 'permanently destroyed', (servers) => for server in servers
        flow = new async
        for server in servers
          ((server) ->
            # TODO introduce parallel option, with intercepted + colorized log output
            flow.serial (next) ->
              borg.destroy fqdn: server.fqdn, next
          )(server)
        flow.go ->
          process.exit 0
      return

  return
























# TODO: restore vbox integration again
#{networks, datacenters, clients, each_machine_instance, get_instance_attrs} = require './Network'
#module.exports = ->
#  vbox_conf = require path.join process.cwd(), 'attributes', 'virtualbox'
#  { boxes } = vbox_conf
#  VBoxProxyClient = require '../cloud/VBoxProxyClient'
#  client = new VBoxProxyClient()
#  vboxmanage = (args, cb) ->
#    console.log JSON.stringify args
#    #return cb()
#    client.connect vbox_conf.host, vbox_conf.port, ->
#      client.command args,
#        spawn: (pid) ->
#          console.log 'pid', pid
#          return
#        stdout: (data) ->
#          console.log 'stdout', data
#          return
#        stderr: (data) ->
#          console.log 'stderr', data
#          return
#        error: (err) ->
#          console.log 'error', err
#          return
#        close: (code) ->
#          console.log 'close', code
#          if code is 0
#            console.log 'success.'
#          else
#            console.log 'fail!'
#          client.close()
#          cb() if typeof cb is 'function'
#          return
#      return
#    return
#
#  switch process.argv[3]
#    when 'list'
#      each_machine_instance ({ machine, instance }) ->
#        attrs = get_instance_attrs "#{machine}#{instance}"
#        console.log attrs._name
#
#    when 'create'
#      attrs = get_instance_attrs process.argv[4]
#      console.log 'found machine', JSON.stringify attrs, null, 2
#
#      flow = new async
#
#      flow.serial (next) ->
#        vboxmanage ['import', boxes[attrs.box].path, '--vsys', 0, '--ostype', boxes[attrs.box].ostype, '--vmname',
#        attrs._name, '--cpus', attrs.cpus, '--memory', attrs.memory, '--unit', 4, '--ignore'], next
#
#      # create natnetwork
#      _.each networks[attrs.datacenter].nat_networks, (nat_network, name) ->
#        nat_network._name = "#{attrs.datacenter}_#{name}".underscore()
#        flow.serial (next) ->
#          vboxmanage [ 'natnetwork', 'add', '-t', nat_network._name, '-n', nat_network.cidr, '-e', '-h', (nat_network.dhcp or 'on') ], next
#        # configure natnetwork ssh port forward
#        if nat_network.ssh_port_forward is true and attrs._random_ssh_port and attrs._ssh_nic_ip and attrs._ssh_nic_port
#          flow.serial (next) ->
#            vboxmanage [ 'natnetwork', 'modify', '-t', nat_network._name, '-p', "ssh:tcp:[#{vbox_conf.host}]:#{attrs._random_ssh_port}:[#{attrs._ssh_nic_ip}]:#{attrs._ssh_nic_port}" ], next
#
#      # configure interface(s)
#      _.each [0, 1, 2, 3], (i) ->
#        if attrs.network["eth#{i}"]?.attach?
#          switch attrs.network["eth#{i}"].attach
#            when 'disconnected'
#              flow.serial (next) ->
#                vboxmanage [ 'modifyvm', attrs._name, "--nic#{i+1}", 'null', "--cableconnected#{i+1}", 'off' ], next
#            when 'natnetwork'
#              flow.serial (next) ->
#                vboxmanage [ 'modifyvm', attrs._name, "--nic#{i+1}", 'natnetwork', "--nat-network#{i+1}", "#{attrs.datacenter}_#{attrs.network["eth#{i}"].natnetwork}".underscore(), "--cableconnected#{i+1}", 'on' ], next
#
#      # start the machine backgrounded
#      flow.serial (next) ->
#        vboxmanage ['startvm', attrs._name], next #, '--type', 'headless'], next
#
#      flow.go ->
#        # TODO: kick-start assimilate
#
#    when 'assimilate'
#      attrs = get_instance_attrs process.argv[4]
#      Borg = require './Borg'
#      target = "#{boxes[attrs.box].user}:#{boxes[attrs.box].pass}@localhost:22"
#      options = role: attrs._name
#      console.log JSON.stringify target: target, options: options
#      #Borg.assimilate target, options, ->
#      #  console.log 'done'
#
#    when 'use'
#      # TODO: run mocha-based test suite
#      return
#
#    when 'login'
#      #child_process.spawn 'ssh', [], env: process.env, stdio: 'passthru'
#      return
#
#    when 'destroy'
#      attrs = get_instance_attrs process.argv[4]
#      # TODO: shutdown first, but only if running
#      vboxmanage ['controlvm', attrs._name, 'poweroff'], ->
#        vboxmanage ['unregistervm', attrs._name, '--delete'], ->
#          # TODO: delete natnetwork
#          #vboxmanage [ 'natnetwork', 'remove', '-t', datacenter ]
#
#  return
