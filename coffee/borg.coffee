ssh = require './ssh'
cmdr = require 'commander'
pack = require '../package.json'

#process.stdout.write "Hello!\n"

cmdr
  .version(pack.version)
  .command('rekey [nodes]')
  .description('copy ssh public key to authorized_hosts on remote machine(s)')
  .action (nodes) ->
    console.log('setup for %j', nodes)

cmdr.parse process.argv

#ssh "date", (-> console.log "cb" ), ->
#  console.log "exit"

#process.exit 0
