{spawn} = require 'child_process'
{Subscriber, Emitter} = require 'emissary'
_ = require 'underscore-plus'

module.exports =
class Gofmt
  Subscriber.includeInto(this)
  Emitter.includeInto(this)

  constructor: (dispatch) ->
    atom.workspaceView.command 'golang:gofmt', => @formatCurrentBuffer()
    @dispatch = dispatch
    @name = 'fmt'

  destroy: ->
    @unsubscribe()

  reset: (editorView) ->
    @emit 'reset', editorView

  formatCurrentBuffer: ->
    editorView = atom.workspaceView.getActiveView()
    return unless editorView?
    @reset editorView
    @formatBuffer(editorView, false)

  formatBuffer: (editorView, saving) ->
    unless @dispatch.isValidEditorView(editorView)
      @emit @name + '-complete', editorView, saving
      return
    if saving and not atom.config.get('go-plus.formatOnSave')
      @emit @name + '-complete', editorView, saving
      return
    buffer = editorView?.getEditor()?.getBuffer()
    unless buffer?
      @emit @name + '-complete', editorView, saving
      return
    args = ['-w']
    configArgs = @dispatch.splicersplitter.splitAndSquashToArray(' ', atom.config.get('go-plus.gofmtArgs'))
    args = args.concat(configArgs) if configArgs? and _.size(configArgs) > 0
    args = args.concat([buffer.getPath()])
    go = @dispatch.goexecutable.current()
    cmd = go.gofmt()
    done = (exitcode, stdout, stderr) =>
      unless stderr? and stderr isnt ''
        if stdout? and stdout isnt ''
          components = stdout.split(' ')
          go.name = components[2] + ' ' + components[3]
          go.version = components[2]
          go.env = @env
      console.log 'Error running go version: ' + err if err?
      console.log 'Error detail: ' + stderr if stderr? and stderr isnt ''
      # callback(null)
    @dispatch.executor.exec(cmd, false, @dispatch?.env(), done, args)
    errored = false
    proc = spawn(cmd, args)
    proc.on 'error', (error) =>
      return unless error?
      errored = true
      console.log @name + ': error launching command [' + cmd + '] – ' + error  + ' – current PATH: [' + @dispatch.env().PATH + ']'
      messages = []
      message = line: false, column: false, type: 'error', msg: 'Gofmt Executable Not Found @ ' + cmd + ' ($GOPATH: ' + go.buildgopath() + ')'
      messages.push message
      @emit @name + '-messages', editorView, messages
      @emit @name + '-complete', editorView, saving
    proc.stderr.on 'data', (data) => @mapMessages(editorView, data)
    proc.stdout.on 'data', (data) => console.log @name + ': ' + data if data?
    proc.on 'close', (code) =>
      console.log @name + ': [' + cmd + '] exited with code [' + code + ']' if code isnt 0
      @emit @name + '-complete', editorView, saving unless errored

  mapMessages: (editorView, data) ->
    pattern = /^(.*?):(\d*?):((\d*?):)?\s(.*)$/img
    messages = []
    extract = (matchLine) ->
      return unless matchLine?
      message = switch
        when matchLine[4]?
          line: matchLine[2]
          column: matchLine[4]
          msg: matchLine[5]
          type: 'error'
          source: 'fmt'
        else
          line: matchLine[2]
          column: false
          msg: matchLine[5]
          type: 'error'
          source: 'fmt'
      messages.push message
    loop
      match = pattern.exec(data)
      extract(match)
      break unless match?
    @emit @name + '-messages', editorView, messages
