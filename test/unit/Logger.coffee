assert = require('chai').assert
Logger = require '../../Logger'

describe 'Logger', ->
  it 'doesn\'t need instanatiation', ->
    assert.isFunction Logger.out

  it 'can output to the screen'

  it 'can output to a file'

  it 'can output in ansi 16-color'
