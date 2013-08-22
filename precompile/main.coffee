Borg = require './Borg'

switch cmd = process.argv[2]
  when 'rekey', 'assimilate', 'cmd'
    Borg cmd
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
        Usage: borg command [options] <user:password@host ...>

        Options:

          --sudo              use `sudo -i`
          -u=<user>           use `sudo -iu`
          -c=<shell_command>  command to execute

        """
      else
        console.log """
        Usage: borg <command> [options] <host ...>

        Commands:

          rekey       copy ssh public key to authorized_hosts on remote host(s)
          assimilate  bootstrap and cook remote host(s)
          cmd         bulk execute command on remote host(s)

        Options:

          -h, --help     output usage information
          -V, --version  output version number

        """
