class Logger
  @started: new Date
  @out: ->
    switch arguments.length
      when 2
        if typeof arguments[arguments.length-1] is 'function'
          [s, cb] = arguments
        else
          [o, s] = arguments
      when 1 then [s] = arguments
    o ||= {}
    o.type ||= 'info'
    o.type_color =
      info: 'yellow'
      out: 'reset'
      stdin: 'cyan'
      stdout: 'magenta'
      stderr: 'bright_red'
      err: 'bright_red'
    @host = o.host if o.host

    pad = new Array(("#{new Date - @started}ms #{if @host then "#{@host} " else ""}#{if o.type is 'out' then '' else "[#{o.type}] "} ").length).join ' '
    s = s.toString().replace(/\n/g, "\n"+pad) # pad w/ spaces

    process.stdout.write "#{Color.bright_white}#{new Date - @started}ms#{Color.reset} "+
      "#{if @host then "#{RainbowIndex @host}#{@host}#{Color.reset} " else ""}"+
      "#{Color.grey}"+
      "#{if o.type is 'out' then '' else "[#{o.type}] "}"+
      "#{Color.reset}#{Color[o.type_color[o.type]]}"+
      "#{s}"+
      "#{if o.type is 'out' or o.newline is false then "\r" else "\n"}"+
      "#{Color.reset}"

    cb() if typeof cb is 'function'

class RainbowIndex
  @id: 0
  @hash: {}
  @rainbow: (
    'blue magenta cyan red green yellow'+
    'bright_yellow bright_blue bright_magenta '+
    'bright_cyan bright_red bright_green'
  ).split ' '
  constructor: (s) ->
    return Color[RainbowIndex.hash[s] ||= RainbowIndex.rainbow[RainbowIndex.id++ % RainbowIndex.rainbow.length]]

class Color
  @reset:   '\u001b[0m'
  @black:   '\u001b[30m'
  @red:     '\u001b[31m'
  @green:   '\u001b[32m'
  @yellow:  '\u001b[33m'
  @blue:    '\u001b[34m'
  @magenta: '\u001b[35m'
  @cyan:    '\u001b[36m'
  @white:   '\u001b[37m'
  @grey:           '\u001b[1m\u001b[30m'
  @bright_red:     '\u001b[1m\u001b[31m'
  @bright_green:   '\u001b[1m\u001b[32m'
  @bright_yellow:  '\u001b[1m\u001b[33m'
  @bright_blue:    '\u001b[1m\u001b[34m'
  @bright_magenta: '\u001b[1m\u001b[35m'
  @bright_cyan:    '\u001b[1m\u001b[36m'
  @bright_white:   '\u001b[1m\u001b[37m'

module.exports = Logger: Logger, RainbowIndex: RainbowIndex, Color: Color
