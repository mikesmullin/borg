BORG_HELP = """
Usage: borg <command> [options] <host ...>

Commands:

  create      construct hosts in the cloud via provider apis
  assimilate  execute scripted commands via ssh on hosts
  assemble    create and assimilate hosts
  test        simulate assimilation on localhost

Options:

  -h, --help     output usage information
  -V, --version  output version number

"""


BORG_HELP_TEST = """
Usage: borg test <subcommand>

Subcommands:

  list                enumerate servers defined in networks
  create              create localhost virtualbox machine
  assimilate          assimilate the localhost vm
  checkup             test successful assimilation
  login               open ssh sessions to matching hosts
  destroy             delete localhost vm

"""

BORG_HELP_ASSIMILATE = """
Usage: borg assimilate [options] <user:password@host ...>

Options:

  -r, --role  assign each node the following role

"""

BORG_HELP_NONE = "Sorry, no help for that, yet."

switch cmd = process.argv[2]
  when '-V', '--version', 'version'
    pkg = require './package.json'
    console.log "borg v#{pkg.version}\n"

  when 'create', 'assimilate', 'assemble'
    Borg = require './Borg'
    borg = new Borg
    borg[cmd] fqdn: process.argv[3], (err) ->
      if err
        process.stderr.write 'Error: '+err+"\n"
        process.exit 1

  when 'test'
    return console.log BORG_HELP_TEST if process.argv.length <= 3
    (require './test')()

  else # when '-h', '--help', 'help'
    switch process.argv[3]
      when 'assimilate'
        console.log BORG_HELP_ASSIMILATE
      when 'test'
        switch process.argv[4]
          when 'list', 'create', 'assimilate', 'checkup', 'login', 'destroy'
            console.log BORG_HELP_NONE
          else
            console.log BORG_HELP_TEST
      else
        console.log BORG_HELP

