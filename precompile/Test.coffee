path = require 'path'
_ = require 'lodash'

module.exports = ->
  # import the machines array
  require 'coffee-script'
  machines = require path.join process.cwd(), 'machines.coffee'
  {datacenters, clients, boxes} = machines
  tld = 'animaljam.com'

  get_instance_attrs = (name) ->
    for datacenter, v of datacenters
      for machine, vv of machines[datacenter] when not _.contains ['_default', 'runlist_before', 'runlist_after'], machine
        for instance, vvv of vv when name is "#{machine}#{instance}" and not _.contains ['_default'], instance
          instance_attrs = {}
          if machines[datacenter]._default?
            instance_attrs = _.clone machines[datacenter]._default
          if machines[datacenter][machine]._default?
            instance_attrs = _.merge instance_attrs, machines[datacenter][machine]._default
          instance_attrs = _.merge instance_attrs, vvv
          instance_attrs._name = "#{datacenter}.#{machine}#{instance}.#{tld}"
          instance_attrs._natnetwork = datacenter.underscored()
          # TODO: generate random ssh port between 10-20k and save in process.cwd() .borgmeta. look there first to ensure not already assigned and unique. set in attrs.
          instance_attrs._random_ssh_port
          instance_attrs._ssh_nic_ip
          instance_attrs._ssh_nic_port
          return instance_attrs
    throw "cant find machine #{name}. check: borg test list"

  vbox_conf = require path.join process.cwd(), 'virtualbox.coffee'
  VBoxProxyClient = require './VBoxProxyClient'
  client = new VBoxProxyClient()
  vboxmanage = (args, cb) ->
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
      for datacenter, v of datacenters
        for machine, vv of machines[datacenter] when not _.contains ['_default', 'runlist_before', 'runlist_after'], machine
          for instance, vvv of vv when not _.contains ['_default'], instance
            attrs = get_instance_attrs "#{machine}#{instance}"
            console.log attrs._name

    when 'create'
      attrs = get_instance_attrs process.argv[4]
      console.log 'found machine', JSON.stringify attrs, null, 2

      # TODO: move the ostype value inside of .box .metadata file
      vboxmanage ['import', boxes[attrs.box].path, '--vsys', 0, '--ostype', 'Ubuntu_64', '--vmname',
        attrs._name, '--cpus', attrs.cpus, '--memory', attrs.memory, '--unit', 4, '--ignore'], ->

        # create natnetwork
        natnetwork = datacenter.underscored()
        vboxmanage [ 'natnetwork', 'add', '-t', attrs._natnetwork, '-n', '172.16/16', '-e', '-h', 'on' ], ->
        # TODO: add IF statements around all these lines
        vboxmanage [ 'setextradata', 'global', "NAT/#{attrs._natnetwork}/SourceIp4", '172.16.0.1' ], ->

        # nic type: unassigned
        vboxmanage [ 'modifyvm', attrs._name, '--nic1', 'null', '--cableconnected1', 'off' ], ->
        vboxmanage [ 'modifyvm', attrs._name, '--nic2', 'null', '--cableconnected2', 'off' ], ->

        # nic type: natnetwork
        vboxmanage [ 'modifyvm', attrs._name, '--nic2', 'natnetwork', '--nat-network2', attrs._natnetwork, '--cableconnected2', 'on' ], ->

        # port forward
        vboxmanage [ 'natnetwork', 'modify', '-t', attrs._natnetwork, '-p', "ssh:tcp:[]:#{attrs._random_ssh_port}:[#{attrs._ssh_nic_ip}]:#{attrs._ssh_nic_port}" ], ->

        # start the machine backgrounded
        vboxmanage ['startvm', attrs._name], -> #, '--type', 'headless'], ->

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
