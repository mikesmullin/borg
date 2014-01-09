# lets you remotely manage a windows virtualbox host (e.g., from a linux guest virtual machine)
# for people who like to develop inside a virtual machine; workaround for vm-inside-a-vm/inception limitation

PORT = 4141
HOST = '0.0.0.0'

net = require 'net'
path = require 'path'
child_process = require 'child_process'

send = (socket, pid, type, data, cb) ->
  data = JSON.stringify pid: pid, type: type, data: data
  console.log data
  socket.write data + "\u0000", 'utf8', cb
  return

server = net.createServer allowHalfOpen: false, (socket) =>
  console.log "new client #{socket.remoteAddress}:#{socket.remotePort} connected to this server"
  socket.on 'error', (err) ->
    console.log "socket error: "+ JSON.stringify err
    return
  buffer = ''
  socket.on 'data', (buf) ->
    # remote can transmit messages split across several packets,
    # as well as more than one message per packet
    buffer += buf.toString()
    while (pos = buffer.indexOf("\u0000")) isnt -1 # we have a complete message
      recv = buffer.substr 0, pos
      buffer = buffer.substr pos+1
      data = JSON.parse recv
      console.log JSON.stringify data, null, 2

      # incoming is a request to launch vbox
      child = child_process.spawn('VBoxManage.exe', data.args, cwd: path.join('C:','Program Files','Oracle','VirtualBox'), env: process.env)
      send socket, child.pid, 'spawn', null, ->
      child.stdout.on 'data', (data) ->
        send socket, child.pid, 'stdout', data.toString(), ->
        return
      child.stderr.on 'data', (data) ->
        send socket, child.pid, 'stderr', data.toString(), ->
        return
      child.on 'error', (err) ->
        send socket, child.pid, 'error', err, ->
        return
      child.on 'close', (code) ->
        send socket, child.pid, 'close', code, ->
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

# begin listening
server.listen PORT, HOST, ->
  console.log "listening on tcp/#{HOST}:#{PORT}"
  return
