require 'sugar'
_     = require 'lodash'
path  = require 'path'
async = require 'async2'
{ delay } = require '../util'
Borg = require '../Borg'
borg = new Borg

module.exports = ->
  cloud_provider = 'aws' # hard-coded for now

  switch process.argv[3]
    when 'list'
      borg.flattenNetworkAttributes()
      last_group = undefined
      count = 0
      borg.eachServer ({ server }) ->
        if null isnt server.fqdn.match new RegExp process.argv[4], 'g'
          count++
          if server.group isnt last_group
            console.log "\n# #{server.datacenter} #{server.group}"
            last_group = server.group
          console.log "#{server.private_ip or server.public_ip or '#'} #{server.fqdn}"
      console.log "\n#{count} server(s) found.\n"

    when 'create'
      attrs = get_instance_attrs process.argv[4]
      console.log 'found machine', JSON.stringify attrs, null, 2

      flow = new async

      # TODO: move the ostype value inside of .box .metadata file
      flow.serial (next) ->
        vboxmanage ['import', boxes[attrs.box].path, '--vsys', 0, '--ostype', 'Ubuntu_64', '--vmname',
        attrs._name, '--cpus', attrs.cpus, '--memory', attrs.memory, '--unit', 4, '--ignore'], next

      # create natnetwork
      _.each networks[attrs.datacenter].nat_networks, (nat_network, name) ->
        nat_network._name = "#{attrs.datacenter}_#{name}".underscore()
        flow.serial (next) ->
          vboxmanage [ 'natnetwork', 'add', '-t', nat_network._name, '-n', nat_network.cidr, '-e', '-h', (nat_network.dhcp or 'on') ], next
        # configure natnetwork ssh port forward
        if nat_network.ssh_port_forward is true and attrs._random_ssh_port and attrs._ssh_nic_ip and attrs._ssh_nic_port
          flow.serial (next) ->
            vboxmanage [ 'natnetwork', 'modify', '-t', nat_network._name, '-p', "ssh:tcp:[#{vbox_conf.host}]:#{attrs._random_ssh_port}:[#{attrs._ssh_nic_ip}]:#{attrs._ssh_nic_port}" ], next

      # configure interface(s)
      _.each [0, 1, 2, 3], (i) ->
        if attrs.network["eth#{i}"]?.attach?
          switch attrs.network["eth#{i}"].attach
            when 'disconnected'
              flow.serial (next) ->
                vboxmanage [ 'modifyvm', attrs._name, "--nic#{i+1}", 'null', "--cableconnected#{i+1}", 'off' ], next
            when 'natnetwork'
              flow.serial (next) ->
                vboxmanage [ 'modifyvm', attrs._name, "--nic#{i+1}", 'natnetwork', "--nat-network#{i+1}", "#{attrs.datacenter}_#{attrs.network["eth#{i}"].natnetwork}".underscore(), "--cableconnected#{i+1}", 'on' ], next

      # start the machine backgrounded
      flow.serial (next) ->
        vboxmanage ['startvm', attrs._name], next #, '--type', 'headless'], next

      flow.go ->
        # TODO: kick-start assimilate

    when 'assimilate'
      attrs = get_instance_attrs process.argv[4]
      Borg = require './Borg'
      target = "#{boxes[attrs.box].user}:#{boxes[attrs.box].pass}@localhost:22"
      options = role: attrs._name
      console.log JSON.stringify target: target, options: options
      #Borg.assimilate target, options, ->
      #  console.log 'done'

    when 'use'
      # TODO: run mocha-based test suite
      return

    when 'login'
      #child_process.spawn 'ssh', [], env: process.env, stdio: 'passthru'
      return

    when 'destroy'
      attrs = get_instance_attrs process.argv[4]
      # TODO: shutdown first, but only if running
      vboxmanage ['controlvm', attrs._name, 'poweroff'], ->
        vboxmanage ['unregistervm', attrs._name, '--delete'], ->
          # TODO: delete natnetwork
          #vboxmanage [ 'natnetwork', 'remove', '-t', datacenter ]

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
#      # TODO: move the ostype value inside of .box .metadata file
#      flow.serial (next) ->
#        vboxmanage ['import', boxes[attrs.box].path, '--vsys', 0, '--ostype', 'Ubuntu_64', '--vmname',
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
