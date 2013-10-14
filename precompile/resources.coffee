_ = require 'underscore'
async = require 'async2'
do_if = (test, try_f, cb) ->
  if test
    try_f(cb)
  else
    cb()
_static = (k, v) ->
  if global[k]
    false
  else
    global[k] = v
_.extend global,
  install: (packages, o, cb) ->
    Logger.out 'installing packages'
    do_if _static('__apt_update_happened', true),
      ((done)-> ssh.cmd "sudo apt-get update", done ), ->
        ssh.cmd "sudo apt-get install -y #{packages}", cb

  execute: (cmd, o, cb) ->
  deploy_revision: (name, o, cb) ->
  put_file: (src, o, cb) ->
  put_template: (src, o, cb) ->
  cron: (name, o, cb) ->
