module.exports = new: ->
  Q = []
  Q.then = (fn, args...) -> Q.push(-> args.push Q.next; fn.apply null, args); @
  Q.next = (err) -> Q.splice 0, Q.length-1 if err; Q.shift()?.apply null, arguments
  Q.finally = -> Q.then.apply null, arguments; Q.next()
  Q
