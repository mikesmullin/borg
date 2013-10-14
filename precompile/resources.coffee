_ = require 'underscore'
_.extend global,
  install: (packages, cb) ->
    Logger.out 'installing packages'
    ssh.cmd "sudo apt-get update", ->
      ssh.cmd "sudo apt-get install -y #{packages}", ->
        cb()

  execute: (cmd) ->
  deploy_revision: (name, o) ->
  put_file: (src, target) ->
  put_template: (src, target) ->
  cron: (name, o) ->
