_ = require 'underscore'
path = require 'path'
async = require 'async2'
skip_if = (test, try_f, cb) -> if test then try_f(cb) else cb()
_static = (k, v) -> if global[k] then false else global[k] = v
_.extend global,
  install: (packages, o, cb) ->
    return cb()
    skip_if _static('__apt_update_happened', true),
      ((cb)-> ssh.cmd 'sudo apt-get update', cb), {}, ->
        ssh.cmd "sudo apt-get install -y #{packages}", {}, cb

  execute: (cmd, o, cb) ->
    ssh.cmd cmd, {}, cb

  deploy_revision: (name, o, cb) ->
    # TODO: support git and svn
    # TODO: support shared dir, cached-copy, and symlinking logs and other stuff
    # TODO: support keep_releases
    releases_dir = path.join o.deploy_to, 'releases'
    ssh.cmd "sudo mkdir -p #{releases_dir}", {}, ->
      out = ''
      ssh.cmd "svn info --username #{o.svn_username} --password #{o.svn_password} --revision #{o.revision} #{o.svn_arguments} #{o.repository}", (data: (data, type) ->
        out += data.toString() if type isnt 'stderr'
      ), (code, signal) ->
        die 'svn info failed' unless code is 0
        die 'svn revision not found' unless current_revision = ((m = out.match /^Revision: (\d+)$/m) && m[1])
        release_dir = path.join releases_dir, current_revision
        ssh.cmd "sudo mkdir -p #{release_dir}", {}, ->
          ssh.cmd "sudo chown -R #{o.user}.#{o.group} #{release_dir}", {}, ->
            ssh.cmd "sudo -u#{o.user} svn checkout --username #{o.svn_username} --password #{o.svn_password} #{o.repository} --revision #{current_revision} #{o.svn_arguments} #{release_dir}", {}, ->
              current_dir = path.join o.deploy_to, 'current'
              link release_dir, current_dir, cb

  link: (src, target, cb) ->
    ssh.cmd "[ -h #{target} ] && sudo rm #{target}; sudo ln -s #{src} #{target}", {}, cb

  put_file: (src, o, cb) ->
    ssh.cmd "sudo touch #{o.target}", {}, cb

  put_template: (src, o, cb) ->
    ssh.cmd "sudo touch #{o.target}", {}, cb

  cron: (name, o, cb) ->
    cb()
