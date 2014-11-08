Borg = require './Borg'
borg = new Borg

switch cmd = process.argv[1]
  when '-V', '--version', 'version'
    pkg = require '../package.json'
    console.log """
    borg v#{pkg.version}

    """
  when 'create', 'assimilate', 'assemble', 'cmd'
    borg[cmd] fqdn: process.argv[2], (err) ->
      if err
        process.stderr.write 'Error: '+err+"\n"
        process.exit 1

  when 'test'
    (require './Test')()

  else # when '-h', '--help', 'help'
    switch process.argv[2]
      when 'assimilate'
        console.log """
        Usage: borg assimilate [options] <user:password@host ...>

        Options:

          -r, --role  assign each node the following role

        """
      when 'cmd'
        console.log """
        Usage: borg cmd options] <user:password@host ...> -- <shell_command>

        """
      when 'test'
        switch process.argv[3]
          when 'list' then 1
          when 'create'
            console.log 'Not implemented, yet.'
          when 'assimilate'
            console.log 'Not implemented, yet.'
          when 'checkup'
            console.log 'Not implemented, yet.'
          when 'login'
            console.log 'Not implemented, yet.'
          when 'destroy'
            console.log 'Not implemented, yet.'
          else
            console.log """
            Usage: borg test <subcommand>

            Subcommands:

              list                enumerate servers defined in networks
              create              create localhost virtualbox machine
              assimilate          assimilate the localhost vm
              checkup             test successful assimilation
              login               open ssh sessions to matching hosts
              destroy             delete localhost vm

            """
      else
        console.log """
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
