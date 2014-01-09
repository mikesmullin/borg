assert = require('chai').assert
global.Logger = out: ->
VBoxProxyClient = require '../../VBoxProxyClient'

describe.only 'VBoxProxyClient', ->
  client = new VBoxProxyClient()

  it 'can connect', (done) ->
    #client.connect '10.1.10.49', 4141, done()
    client.connect 'localhost', 4141, done()

  it 'send commands', (done) ->
    client.command ['/help'],
      spawn: (pid) ->
        console.log 'pid', pid
      stdout: (data) ->
        console.log 'stdout', data
      stderr: (data) ->
        console.log 'stderr', data
      error: (err) ->
        console.log 'error', err
      close: (code) ->
        console.log 'close', code
        assert.equal code, -1
        done()

  it 'can disconnect', ->
    client.close()
