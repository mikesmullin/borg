_ = require 'lodash'
child_process = require 'child_process'
path = require 'path'
fs = require 'fs'

global.USING_CLI = true

BORG_DOCS_AD = """

Advertisement:

  Learn to Script Borg from the pros:
  http://mikesmullin.github.io/borg-docs/

"""

BORG_HELP = """
Usage: borg <command> [options] <host ...>

Performs devops server orchestration, remote provisioning,
testing, and deployment.

Commands:

  init        create necessary files for a new project
  install     add third-party dependency Git submodules
  update      update third-party dependency Git submodules
  list        enumerate available hosts
  create      construct hosts in the cloud via provider apis
  assimilate  execute scripted commands via ssh on hosts
  assemble    alias for create + assimilate
  destroy     terminate existing hosts
  login       bulk open clusterssh to matching hosts
  test        simulate assimilation on localhost
  encrypt     encrypt files for secure sharing
  version     display currently installed version
  help        display more information about a command

"""+BORG_DOCS_AD

BORG_HELP_INIT = """
Usage: borg init <directory>

Creates a new directory by the given name in the current
working directory, and places templates representing the
files necessary for a new Borg project.

"""

BORG_HELP_INSTALL = """
Usage: borg install <repo>

Installs third-party dependencies as Git submodules located
under ./scripts/vendor/

Options:

  -v=         fetches a specific branch, tag, or git ref

"""

BORG_HELP_UPDATE = """
Usage: borg update

Updates third-party dependencies installed as Git submodules.
Especially useful when a branch was specified with -v option
when adding the submodule; update would bring submodule to
the latest commit on that branch.

"""

BORG_HELP_LIST = """
Usage: borg list

Displays a list of all hosts found in `networks.coffee` and
`memory.json` for the current project.

"""

BORG_HELP_CREATE = """
Usage: borg create <fqdn>

Tells cloud provider to create a new virtual machine for
the server matching the given network-defined FQDN.

"""

BORG_HELP_ASSIMILATE = """
Usage: borg assimilate [options] <fqdn>

Executes shell commands over SSH for the purpose of
installing and configuring services on a remote machine
matching the given network-defined FQDN.

Options:

  --locals=   one-time attribute override values given as CSON
  --save      memorize locals given for future use

CSON Format:

  CoffeeScript Object Notation is like JSON but better.

"""+BORG_DOCS_AD

BORG_HELP_ASSEMBLE = """
Usage: borg assemble <fqdn>

Executes `borg create` and `borg assemble` for the server
matching the given network-defined FQDN.

"""

BORG_HELP_DESTROY = """
Usage: borg destroy <fqdn>

Tells cloud provider to terminate the virtual machine
matching the given network-defined FQDN.

"""

BORG_HELP_LOGIN = """
Usage: borg login [options] <fqdn|regex>

Spawn an external ClusterSSH `cssh` process passing one or more
remote host IP and TCP port arguments for each network-defined
FQDN matching the provided regular expression.

NOTICE: `cssh` binary is 3rd-party dependency; install separately.

Options:

  --locals=   one-time attribute override values given as CSON
  --save      bulk memorize locals given for future use

FQDN RegEx:

  Double-quoted, escaped string. Omit delimiters.

CSON Format:

  CoffeeScript Object Notation is like JSON but better.

"""

BORG_HELP_CRYPT = """
Usage: borg encrypt|decrypt <file ...>

Symmetrically crypt file(s) on disk using AES-256-CBC and
a `./secret` you provide in the cwd. This makes them safer to
share with others (e.g., via an untrusted medium or repository)
as long as you do not also share `./secret` the same way.

These files are be readable by Borg, and are optionally
decrypted when required for upload to remote hosts.

"""

BORG_HELP_TEST = """
Usage: borg test <subcommand> <fqdn|regex>

Performs testing version of otherwise normal operations,
across network-defined FQDNs matching the provided regular
expression; aiding in development and integrity validation.

Subcommands:

  list        enumerate available test hosts
  create      construct new test hosts
  assimilate  execute scripts on existing test hosts
  assemble    alias for create + assimilate + checkup
  checkup     execute test suite against existing hosts
  destroy     terminate existing test hosts

FQDN RegEx:

  Double-quoted, escaped string. Omit delimiters.

Other notes:

  Hosts created by this command will have a "test-" FQDN prefix.

"""

BORG_HELP_NONE = "Sorry, no help for that, yet."
INVALID = "Invalid command. Type `borg help` for help.\n"

OPTION = /^--?(\w+)\s*=?\s*(.*)$/
argv = []; options = {}; args = process.argv.slice 2
while args.length
  arg = args.shift()
  if null isnt matches = arg.match OPTION
    [nil, key, value] = matches
    if key and value
      options[key] = value
    else if key
      options[key] = true
  else
    argv.push arg
process.args = argv
if options.locals # allow users to pass CSON via --locals cli argument
  options.locals = eval (require 'coffee-script').compile options.locals, bare: true
process.options = options

borg = ''
init_borg = ->
  Borg = require './index'
  borg = new Borg

delegate_borg = (cmd) ->
  init_borg()
  borg[cmd] fqdn: process.args[1], (err) ->
    if err
      process.stderr.write 'Error: '+err+"\n"
      console.trace()
      process.exit 1


return console.log BORG_HELP if process.args.length is 0
switch cmd = process.args[0]
  when '-V', '--version', 'version'
    pkg = require path.join __dirname, '..', 'package.json'
    console.log "borg v#{pkg.version}\n"

  when 'init'
    project_dir = path.join process.cwd(), process.args[1]
    console.log "Initializing empty Borg project in #{project_dir}"
    child_process.exec """
    mkdir -p #{project_dir}
    cd #{project_dir}
    cat << EOF > .gitignore
    node_modules/
    scripts/vendor/
    !.gitkeep
    /cli.coffee
    /secret
    EOF
    mkdir -p attributes/ scripts/servers/ scripts/vendor/
    touch README.md scripts/servers/.gitkeep scripts/vendor/.gitkeep attributes/networks.coffee
    echo {} > attributes/memory.json
    openssl rand -base64 512 > secret
    git init
    borg install resources
    """,
    (error, stdout, stderr) ->
      process.stderr.write(error+'\n') and process.exit 1 if error
      process.stdout.write stdout
      process.stderr.write stderr

  when 'install'
    return console.log BORG_HELP_INSTALL if process.args.length <= 1
    repo = process.args[1]
    name = path.basename repo, '.git'
    if null is repo.match /\//
      repo = 'borg-scripts/'+repo # assume borg-scripts/ if no repo specified
    if null is repo.match /:/
      repo = 'git@github.com:'+repo+'.git' # assume github if no host specified
    cmd = """
    git submodule add -f#{if options.v then " -b "+options.v else ''} #{repo} scripts/vendor/#{name}
    cd scripts/vendor/#{name} && npm install
    """
    console.log cmd
    child_process.exec cmd, (error, stdout, stderr) ->
      process.stderr.write(error+'\n') and process.exit 1 if error
      process.stdout.write stdout
      process.stderr.write stderr

  when 'update'
    cmd = """
    git submodule update --init --remote
    """
    submodules = fs.readdirSync path.join process.cwd(), 'scripts', 'vendor'
    for submodule in submodules when not submodule.match /^\./
      cmd += "\ncd scripts/vendor/#{submodule} && npm update && cd -"
    console.log cmd
    child_process.exec cmd, (error, stdout, stderr) ->
      process.stderr.write(error+'\n') and process.exit 1 if error
      process.stdout.write stdout
      process.stderr.write stderr

  when 'list'
    delegate_borg cmd

  when 'create'
    return console.log BORG_HELP_CREATE if process.args.length <= 1
    delegate_borg cmd

  when 'assimilate'
    return console.log BORG_HELP_ASSIMILATE if process.args.length <= 1
    delegate_borg cmd

  when 'assemble'
    return console.log BORG_HELP_ASSEMBLE if process.args.length <= 1
    delegate_borg cmd

  when 'destroy'
    return console.log BORG_HELP_DESTROY if process.args.length <= 1
    delegate_borg cmd

  when 'login'
    return console.log BORG_HELP_LOGIN if process.args.length <= 1
    rx = new RegExp process.args[1], 'g'
    init_borg()
    borg.flattenNetworkAttributes()
    servers = []
    borg.eachServer ({ server }) ->
      if null isnt server.fqdn.match(rx)
        servers.push server
    if servers.length
      console.log "Will connect to the following servers:\n"
      for server in servers
        if process.options.locals
          _.merge server, process.options.locals
        console.log "  #{server.ssh.host}:#{server.ssh.port} \t#{server.fqdn}"
      if process.options.save
        console.log "\nWill bulk remember instance locals:\n"+JSON.stringify process.options.locals
      borg.cliConfirm "Proceed?", ->
        args = []
        for server in servers
          if process.options.save
            borg.remember "/#{server.fqdn}", process.options.locals
          args.push "#{server.ssh.host}:#{server.ssh.port}"
        child_process.spawn 'cssh', args, stdio: 'inherit'
    else
      process.stderr.write "\n0 existing network server definition(s) found.#{if rx then ' FQDN RegEx: '+rx else ''}\n\n"

  when 'test'
    return console.log BORG_HELP_TEST if process.args.length <= 1
    init_borg()
    switch process.args[1]
      when 'list', 'create', 'assimilate', 'assemble', 'checkup', 'destroy'
        (require './test')(borg)
      else
        console.log INVALID+BORG_HELP_TEST

  when 'encrypt', 'decrypt'
    return console.log BORG_HELP_CRYPT if process.args.length <= 1
    init_borg()
    for file in process.args.slice 1
      file_path = path.join process.cwd(), file
      console.log "#{cmd}ing: #{file_path}..."
      # TODO: make this work in chunks as to not exhaust available memory with large files
      fs.writeFileSync file_path, borg[cmd] fs.readFileSync file_path
    process.exit 0

  when '-h', '--help', 'help'
    if process.args.length is 1
      console.log BORG_HELP
    else
      switch process.args[1]
        when 'init'
          console.log BORG_HELP_INIT
        when 'install'
          console.log BORG_HELP_INSTALL
        when 'update'
          console.log BORG_HELP_UPDATE
        when 'list'
          console.log BORG_HELP_LIST
        when 'create'
          console.log BORG_HELP_CREATE
        when 'assimilate'
          console.log BORG_HELP_ASSIMILATE
        when 'assemble'
          console.log BORG_HELP_ASSEMBLE
        when 'destroy'
          console.log BORG_HELP_DESTROY
        when 'login'
          console.log BORG_HELP_LOGIN
        when 'test'
          if process.args.length is 2
            console.log BORG_HELP_TEST
          else
            switch process.args[2]
              when 'list', 'create', 'assimilate', 'assemble', 'checkup', 'destroy'
                console.log BORG_HELP_NONE
              else
                console.log INVALID
        when 'encrypt', 'decrypt'
          console.log BORG_HELP_CRYPT
        when 'version'
          console.log "Really?"
        when 'help'
          console.log "Give me a break!"
        else
          console.log INVALID
  else
    console.log INVALID
