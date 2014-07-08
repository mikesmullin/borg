_ = require 'lodash'
path = require 'path'
async = require 'async2'
crypto = require 'crypto'

#_static = (k, v) -> if global[k] then false else global[k] = v
#skip_if = (test, try_f, cb) -> if test then try_f(cb) else cb()
did_update = false

module.exports = -> _.assign @,
  install: (packages, cb) =>
    ((next) =>
      return next() if did_update
      @ssh.cmd 'sudo apt-get update', ->
        did_update = true
        next()
    )(=>
      @ssh.cmd "sudo apt-get install -y #{packages}", cb
    )

  # the second time you have to use execute,
  # you probably should create a new resource instead
  execute: (cmd, [o]..., cb) =>
    @ssh.cmd.apply @ssh, arguments

  deploy_revision: (name, [o]..., cb) =>
    # TODO: support git and svn
    # TODO: support shared dir, cached-copy, and symlinking logs and other stuff
    # TODO: support keep_releases
    releases_dir = path.join o.deploy_to, 'releases'
    @ssh.cmd "sudo mkdir -p #{releases_dir}", {}, =>
      out = ''
      @ssh.cmd "svn info --username #{o.svn_username} --password #{o.svn_password} --revision #{o.revision} #{o.svn_arguments} #{o.repository}", (data: (data, type) ->
        out += data.toString() if type isnt 'stderr'
      ), (code, signal) =>
        @die 'svn info failed' unless code is 0
        @die 'svn revision not found' unless current_revision = ((m = out.match /^Revision: (\d+)$/m) && m[1])
        release_dir = path.join releases_dir, current_revision
        @ssh.cmd "sudo mkdir -p #{release_dir}", {}, =>
          @ssh.cmd "sudo chown -R #{o.user}.#{o.group} #{release_dir}", {}, =>
            @ssh.cmd "sudo -u#{o.user} svn checkout --username #{o.svn_username} --password #{o.svn_password} #{o.repository} --revision #{current_revision} #{o.svn_arguments} #{release_dir}", {}, ->
              current_dir = path.join o.deploy_to, 'current'
              link release_dir, current_dir, cb

  link: (src, target, cb) =>
    @ssh.cmd "[ -h #{target} ] && sudo rm #{target}; sudo ln -s #{src} #{target}", {}, cb

  put_file: (src, [o]..., cb) =>
    tmp_file = path.join '/', 'tmp', crypto.createHash('sha1').update(''+ (new Date()) + Math.random()).digest('hex')
    @log "sftp local file #{src} to #{tmp_file}"
    @ssh.put src, tmp_file, (err) =>
      return cb err if err
      @ssh.cmd "sudo chown #{o.user or 'root'}.#{o.user or 'root'} #{tmp_file}", {}, =>
        @ssh.cmd "sudo mv #{tmp_file} #{o.target}", {}, cb

  put_template: (src, [o]..., cb) =>
    # TODO: find out how to put a string via sftp
    @put_file.apply @, arguments

  cron: (name, [o]..., cb) ->
    cb()

  #directory: (name, [o]..., cb) =>
  #  ((next)=>
  #    @execute "#{if o?.sudo then 'sudo ' else ''}mkdir #{if o?.recursive then '-p ' else ''}#{if o?.chmod then '-m'+o.chmod+' ' else ''}#{name}", next
  #  )(=>((next)=>
  #    return next() unless o?.user or o?.group
  #    @execute "#{if o?.sudo then 'sudo ' else ''}chown #{o?.user}:#{o?.group} #{name}", next
  #  )(cb))
