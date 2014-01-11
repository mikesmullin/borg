path = require 'path'
_ = require 'lodash'

module.exports = ->
  # import the machines array
  require 'coffee-script'
  machines = require path.join process.cwd(), 'machines.coffee'
  datacenters = machines.datacenters
  clients = machines.clients
  tld = 'animaljam.com'

  switch process.argv[3]
    when 'list'
      for datacenter, v of datacenters
        for machine, vv of machines[datacenter] when not _.contains ['_default', 'runlist_before', 'runlist_after'], machine
          for instance, vvv of vv when not _.contains ['_default'], instance
            console.log "#{datacenter}.#{machine}#{instance}.#{tld}"

    when 'create'
      name = process.argv[4]
      attrs = (->
        for datacenter, v of datacenters
          for machine, vv of machines[datacenter] when not _.contains ['_default', 'runlist_before', 'runlist_after'], machine
            for instance, vvv of vv when name is "#{machine}#{instance}" and not _.contains ['_default'], instance
              instance_attrs = {}
              if machines[datacenter]._default?
                instance_attrs = _.clone machines[datacenter]._default
              if machines[datacenter][machine]._default?
                instance_attrs = _.merge instance_attrs, machines[datacenter][machine]._default
              return _.merge instance_attrs, vvv
        throw "cant find machine #{name}. check: borg test list"
      )()
      console.log 'found machine', JSON.stringify attrs, null, 2

      vbox_conf = require path.join process.cwd(), 'virtualbox.coffee'
      VBoxProxyClient = require './VBoxProxyClient'
      client = new VBoxProxyClient()
      # TODO: support vbox networking settings
      client.connect vbox_conf.host, vbox_conf.port, ->
        client.command ['import', machines.boxes[attrs.box], '--vsys', 0, '--ostype', 'Ubuntu_64', '--vmname',
          "#{datacenter}.#{machine}#{instance}.#{tld}", '--cpus', attrs.cpus, '--memory', attrs.memory, '--unit', 4, '--ignore'],
          spawn: (pid) ->
            console.log 'pid', pid
          stdout: (data) ->
            console.log 'stdout', data
          stderr: (data) ->
            console.log 'stderr', data
          error: (err) ->
            console.log 'error', err
          close: (code) ->
            console.log 'close', code
            if code is 0
              console.log 'success.'
            else
              console.log 'fail!'
            client.close()
