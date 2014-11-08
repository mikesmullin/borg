Borg = require './Borg'
borg = new Borg

switch cmd = process.argv[2]
  when 'create', 'assimilate', 'assemble', 'cmd'
    borg[cmd] fqdn: process.argv[3], (err) ->
      if err
        process.stderr.write 'Error: '+err+"\n"
        process.exit 1
  when 'test'
    (require './Test')()
  when '-V', '--version', 'version'
    pkg = require '../package.json'
    console.log """
    borg v#{pkg.version}

    """
  #when '-h', '--help', 'help'
  else
    switch process.argv[3]
      when 'rekey'
        console.log """
        Usage: borg rekey [options] <user:password@host ...>

        Options:

          -i  identity file path

        """
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
        switch process.argv[4]
          when 'list' then 1
          #when 'create'
          #when 'assimilate'
          #when 'use'
          #when 'login'
          #when 'destroy'
          else
            console.log """
            Usage: borg test <subcommand>

            Subcommands:

              list                list all machines
              create              create localhost virtualbox machine
              assimilate          assimilate the localhost vm
              use                 test successful assimilation
              login               open ssh session
              destroy             delete localhost vm

            """
      else
        console.log """
        Usage: borg <command> [options] <host ...>

        Commands:

          create      construct hosts in the cloud via provider apis
          rekey       copy ssh public key to authorized_hosts on remote host(s)
          assimilate  execute scripted commands via ssh on hosts
          assemble    provision and assimilate hosts
          cmd         bulk execute command on hosts
          test        simulate assimilation on localhost

        Options:

          -h, --help     output usage information
          -V, --version  output version number

        """
