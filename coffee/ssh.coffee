module.export = ssh = (command, callback, exitCallback) ->
  throw new Error(@address + ": No command to run")  unless command
  user = @user
  options = @sshOptions
  mask = @logMask
  stars = undefined
  args = ["-l" + user, @address, "''" + command + "''"]
  child = undefined
  args = options.concat(args)  if options
  if mask
    stars = star(mask)
    command = command.replace(mask, stars)  while command.indexOf(mask) isnt -1
  @log user + ":ssh: " + command
  child = spawn("ssh", args)
  @listen child, callback, exitCallback
