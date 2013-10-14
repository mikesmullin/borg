_ = require 'underscore'
_.extend global,
  install: (packages) ->
    console.log "would install #{packages}"

  execute: (cmd) ->
  deploy_revision: (name, o) ->
  put_file: (src, target) ->
  put_template: (src, target) ->
  cron: (name, o) ->
