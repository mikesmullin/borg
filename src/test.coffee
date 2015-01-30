process.stdin.setEncoding 'utf8'
require 'sugar'
_     = require 'lodash'
path  = require 'path'
async = require 'async2'
delay = (s,f) -> setTimeout f, s

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
