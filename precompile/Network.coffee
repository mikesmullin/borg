# import the networks object
path = require 'path'
require 'coffee-script'
_ = require 'lodash'
networks = require path.join process.cwd(), 'attributes', 'networks'
{datacenters, clients} = networks

module.exports = Network =
  networks: networks
  datacenters: datacenters
  clients: clients

  each_machine_instance: (cb) ->
    for datacenter, v of datacenters
      for machine, vv of networks[datacenter] when not _.contains ['_default', 'nat_networks'], machine
        for instance, vvv of vv when not _.contains ['_default'], instance
          return if false is cb datacenter: datacenter, machine: machine, instance: instance

  fqdn: (attrs) ->
    "#{attrs.datacenter}.#{attrs.env}.#{attrs.machine}#{attrs.instance}.#{attrs.tld}"

  get_instance_attrs: (name) ->
    r = null
    Network.each_machine_instance ({ datacenter, machine, instance }) ->
      # flatten attributes enough to determine name
      attrs = {}
      if networks[datacenter]._default?
        attrs = _.clone networks[datacenter]._default
      if networks[datacenter][machine]._default?
        attrs = _.merge attrs, networks[datacenter][machine]._default
      attrs = _.merge attrs, networks[datacenter][machine][instance]
      attrs.environment ||= 'development'
      attrs.env = switch attrs.environment
        when 'production' then 'prod'
        when 'staging' then 'stage'
        when 'development' then 'dev'
        else 'dev'
      attrs.datacenter = datacenter
      attrs.machine = machine
      attrs.instance = instance
      attrs._name = Network.fqdn attrs

      # match name
      return unless name is attrs._name or # exact match
        null isnt (new RegExp(name)).exec(attrs._name) # regex match

      # continue parsing attributes
      _.each [0, 1, 2, 3], (i) ->
        if attrs.network["eth#{i}"]?.ssh_port_forward is true and attrs.network["eth#{i}"].address?
          # TODO: generate random ssh port between 10-20k and save in process.cwd() .borgmeta. look there first to ensure not already assigned and unique. set in attrs.
          attrs._random_ssh_port = 22202
          attrs._ssh_nic_ip = attrs.network["eth#{i}"].address
          attrs._ssh_nic_port = 22
          return false # stop looping
      r = attrs
      return false # stop looping
    return r or throw "cant find machine #{name}. check: borg test list"
