path = require 'path'
_ = require 'lodash'
require 'sugar'
async = require 'async2'

module.exports = ->
  # import the networks array
  require 'coffee-script'
  networks = require path.join process.cwd(), 'attributes', 'networks'
  {datacenters, clients} = networks
  tld = 'animaljam.com'

  each_machine_instance = (cb) ->
    for datacenter, v of datacenters
      for machine, vv of networks[datacenter] when not _.contains ['_default', 'nat_network'], machine
        for instance, vvv of vv when not _.contains ['_default'], instance
          return if false is cb datacenter: datacenter, machine: machine, instance: instance

  get_instance_attrs = (name) ->
    # TODO: match name as regex
    attrs = null
    each_machine_instance ({ datacenter, machine, instance }) ->
      if name is "#{machine}#{instance}"
        attrs = {}
        if networks[datacenter]._default?
          attrs = _.clone networks[datacenter]._default
        if networks[datacenter][machine]._default?
          attrs = _.merge attrs, networks[datacenter][machine]._default
        attrs = _.merge attrs, networks[datacenter][machine][instance]
        attrs.datacenter = datacenter
        attrs.machine = machine
        attrs.instance = instance
        attrs.environment ||= 'development'
        attrs.env = switch attrs.environment
          when 'production' then 'prod'
          when 'staging' then 'stage'
          when 'development' then 'dev'
          else 'dev'
        attrs._name = "#{datacenter}.#{attrs.env}.#{machine}#{instance}.#{tld}"
        attrs._natnetwork = datacenter.underscore()
        _.each [0, 1, 2, 3], (i) ->
          if attrs.network["eth#{i}"]?.ssh_port_forward is true and attrs.network["eth#{i}"].address?
            # TODO: generate random ssh port between 10-20k and save in process.cwd() .borgmeta. look there first to ensure not already assigned and unique. set in attrs.
            attrs._random_ssh_port = 22202
            attrs._ssh_nic_ip = attrs.network["eth#{i}"].address
            attrs._ssh_nic_port = 22
            return false
        return false
    return attrs or throw "cant find machine #{name}. check: borg test list"

  vbox_conf = require path.join process.cwd(), 'attributes', 'virtualbox'
  { boxes } = vbox_conf
  VBoxProxyClient = require './VBoxProxyClient'
  client = new VBoxProxyClient()
  vboxmanage = (args, cb) ->
    console.log JSON.stringify args
    client.connect vbox_conf.host, vbox_conf.port, ->
      client.command args,
        spawn: (pid) ->
          console.log 'pid', pid
          return
        stdout: (data) ->
          console.log 'stdout', data
          return
        stderr: (data) ->
          console.log 'stderr', data
          return
        error: (err) ->
          console.log 'error', err
          return
        close: (code) ->
          console.log 'close', code
          if code is 0
            console.log 'success.'
          else
            console.log 'fail!'
          client.close()
          cb() if typeof cb is 'function'
          return
      return
    return

  switch process.argv[3]
    when 'list'
      each_machine_instance ({ datacenter, machine, instance }) ->
        attrs = get_instance_attrs "#{machine}#{instance}"
        console.log attrs._name

    when 'create'
      attrs = get_instance_attrs process.argv[4]
      console.log 'found machine', JSON.stringify attrs, null, 2

      flow = new async

      # TODO: move the ostype value inside of .box .metadata file
      flow.serial (next) ->
        vboxmanage ['import', boxes[attrs.box].path, '--vsys', 0, '--ostype', 'Ubuntu_64', '--vmname',
        attrs._name, '--cpus', attrs.cpus, '--memory', attrs.memory, '--unit', 4, '--ignore'], next

      # create natnetwork
      if networks[attrs.datacenter].nat_network?.cidr?
        flow.serial (next) ->
          vboxmanage [ 'natnetwork', 'add', '-t', attrs._natnetwork, '-n', networks[attrs.datacenter].nat_network.cidr, '-e', '-h', (networks[attrs.datacenter].nat_network.dhcp or 'on') ], next
        if networks[attrs.datacenter].nat_network.dhcp_server?
          flow.serial (next) ->
            vboxmanage [ 'setextradata', 'global', "NAT/#{attrs._natnetwork}/SourceIp4", networks[attrs.datacenter].nat_network.dhcp_server ], next
        # configure natnetwork ssh port forward
        if attrs._random_ssh_port and attrs._ssh_nic_ip and attrs._ssh_nic_port
          flow.serial (next) ->
            vboxmanage [ 'natnetwork', 'modify', '-t', attrs._natnetwork, '-p', "ssh:tcp:[]:#{attrs._random_ssh_port}:[#{attrs._ssh_nic_ip}]:#{attrs._ssh_nic_port}" ], next

      # configure interface(s)
      _.each [0, 1, 2, 3], (i) ->
        if attrs.network["eth#{i}"]?.attach?
          switch attrs.network["eth#{i}"].attach
            when 'disconnected'
              flow.serial (next) ->
                vboxmanage [ 'modifyvm', attrs._name, "--nic#{i+1}", 'null', "--cableconnected#{i+1}", 'off' ], next
            when 'natnetwork'
              flow.serial (next) ->
                vboxmanage [ 'modifyvm', attrs._name, "--nic#{i+1}", 'natnetwork', "--nat-network#{i+1}", attrs._natnetwork, "--cableconnected#{i+1}", 'on' ], next

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
