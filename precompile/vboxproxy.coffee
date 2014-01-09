# vboxproxy
# so you can reach a windows host vboxmanage from inside a linux guest vm
#

PORT = 4141
HOST = '0.0.0.0'
PATH = 'C:\Program Files\Oracle\VirtualBox'
CMD  = 'VboxManage.exe'
#PATH = '/bin'
#CMD  = 'echo'

net = require 'net'
path = require 'path'
child_process = require 'child_process'

send = (socket, type, data, cb) ->
  console.log "send: #{type}"
  data = JSON.stringify type: type, data: data.toString()
  console.log data
  socket.write data, 'utf8', cb
  return

server = net.createServer allowHalfOpen: false, (socket) =>
  console.log "new client #{socket.remoteAddress}:#{socket.remotePort} connected to this server"
  socket.on 'error', (err) ->
    console.log "socket error: "+ JSON.stringify err
    return
  socket.on 'data', (buf) ->
    console.log JSON.stringify buf.toString(), null, 2
    args = buf.toString().split('\n')[0].split(' ')

    # incoming is a request to launch vbox
    child = child_process.spawn(CMD, args, cwd: PATH, env: process.env)
    child.stdout.on 'data', (data) ->
      console.log "stdout: #{data}"
      send socket, 'stdout', data, ->
      return
    child.stderr.on 'data', (data) ->
      console.log "stderr: #{data}"
      send socket, 'stderr', data, ->
      return
    child.on 'close', (code) ->
      console.log "child process exited with code #{code}"
      return
    return

  socket.on 'end', ->
    console.log 'server client sent FIN'
    return
  socket.on 'close', =>
    console.log 'server socket closed'
    return
  return
server.on 'error', (err) ->
  console.log 'server error: '+ JSON.stringify err
  return
server.on 'close', ->
  console.log 'server closed'
  return

# begin listening
server.listen PORT, HOST, ->
  console.log "listening on tcp/#{HOST}:#{PORT}"
  #server.on 'connection', cb
  return

#server.close()
