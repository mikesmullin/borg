module.exports = class Logger
  @started: new Date
  @out: (s) ->
    if console?
      current = new Date
      console.log "#{current - @started} | #{s}"
