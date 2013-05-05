module.exports = class Logger
  @started: new Date
  @out: ->
    o = {}
    switch arguments.length
      when 2 then [o, s] = arguments
      when 1 then [s] = arguments
    o.type ||= 'info'

    process.stdout.write "#{new Date - @started}ms #{if o.host then "#{o.host} " else ""}#{unless o.type is 'out' then "[#{o.type}]" else "|"} #{s}#{if o.type is 'out' then "" else "\n"}"
