global.USING_CLI = true

BORG_HELP = """
Usage: borg <command> [options] <host ...>

Performs devops server orchestration, remote provisioning,
testing, and deployment.

Commands:

  list        enumerate available hosts
  create      construct hosts in the cloud via provider apis
  assimilate  execute scripted commands via ssh on hosts
  assemble    alias for create + assimilate
  destroy     terminate existing hosts
  test        simulate assimilation on localhost
  version     display currently installed version
  help        display more information about a command

"""


BORG_HELP_TEST = """
Usage: borg test <subcommand> <fqdn|regex>

Performs scripted operations, including integration tests,
across network-defined FQDNs matching the provided regular
expression; aiding in development and integrity validation.

Subcommands:

  list        enumerate available test hosts
  create      construct new test hosts
  assimilate  execute scripts on existing test hosts
  checkup     execute test suite against existing hosts
  assemble    alias for create + assimilate + checkup
  login       open ssh sessions to matching hosts
  destroy     terminate existing test hosts

FQDN RegEx:

  Double-quoted, escaped string. Omit delimiters.

Other notes:

  Hosts created by this command will have a "test-" FQDN prefix.

"""

BORG_HELP_ASSIMILATE = """
Usage: borg assimilate [options] <user:password@host ...>

Options:

  -r, --role  assign each node the following role

"""

BORG_HELP_NONE = "Sorry, no help for that, yet."
INVALID = "Invalid command.\n\n"

switch cmd = process.argv[2]
  when '-V', '--version', 'version'
    pkg = require './package.json'
    console.log "borg v#{pkg.version}\n"

  when 'list', 'create', 'assimilate', 'assemble', 'destroy'
    Borg = require './Borg'
    borg = new Borg
    borg[cmd] fqdn: process.argv[3], (err) ->
      if err
        process.stderr.write 'Error: '+err+"\n"
        process.exit 1

  when 'test'
    return console.log BORG_HELP_TEST if process.argv.length <= 3
    (require './test')(borg)

  when '-h', '--help', 'help'
    if process.argv.length is 3
      console.log BORG_HELP
    else
      switch process.argv[3]
        when 'assimilate'
          console.log BORG_HELP_ASSIMILATE
        when 'test'
          if process.argv.length is 4
            console.log BORG_HELP_TEST
          else
            switch process.argv[4]
              when 'list', 'create', 'assimilate', 'checkup', 'login', 'destroy'
                console.log BORG_HELP_NONE
              else
                console.log INVALID+BORG_HELP_TEST
        else
          console.log INVALID+BORG_HELP_TEST
  else
    console.log INVALID+BORG_HELP

