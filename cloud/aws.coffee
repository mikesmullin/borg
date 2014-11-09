exec = require('child_process').exec
{ delay } = require '../util'

# interfaces with aws cli;
# which is a dependency that must be pre-installed,
# and configured with your aws api key,
# by you manually before any of this will work.

module.exports = (log) -> Aws =
  jsonCli: (cmd, cb) ->
    child = undefined
    log JSON.stringify cmd: cmd if DEBUG
    child = exec cmd, cwd: process.cwd(), env: process.env, (err, stdout, stderr) ->
      if err isnt null
        log child.pid+'#error: '+ err
        throw err
      if stderr
        log child.pid+'#stderr: '+ stderr
        throw err
      if stdout
        log child.pid+'#stdout: '+ stdout if DEBUG
        data = JSON.parse stdout
        cb null, data

  createInstance: (name, locals, instance_cb, cb) ->
    log "creating one #{name} instance..."
    res = {}
    Aws.jsonCli """
    aws ec2 run-instances \
      --region #{locals.aws_region} \
      --image-id #{locals.aws_image} \
      --count 1 \
      --instance-type #{locals.aws_size} \
      --key-name #{locals.aws_key} \
      #{if locals.aws_security_groups then "--security-groups #{locals.aws_security_groups.join ','}" else ''} \
      #{if locals.aws_security_group_ids then "--security-group-ids #{locals.aws_security_group_ids.join ','}" else ''} \
      #{if locals.aws_subnet then "--subnet-id #{locals.aws_subnet}" else ''} \
      #{if locals.aws_associate_public_ip then "--associate-public-ip-address" else ''} \
      --placement Tenancy=default \
      --block-device-mappings='[ \
        {"DeviceName":"/dev/xvdb","VirtualName":"ephemeral0"}, \
        {"DeviceName":"/dev/xvdc","VirtualName":"ephemeral1"}, \
        {"DeviceName":"/dev/xvdd","VirtualName":"ephemeral2"}, \
        {"DeviceName":"/dev/xvde","VirtualName":"ephemeral3"} \
      ]' \
      ;
    """, (err, data) ->
      instance_cb res.instanceId = data.Instances[0].InstanceId

      waitForInstanceToBecomeReady = -> delay 1000, ->
        Aws.jsonCli """
        aws ec2 describe-instances \
          --region #{locals.aws_region} \
          --instance-id #{res.instanceId} \
          ;
        """, (err, data) ->
          state = data.Reservations[0].Instances[0].State.Name
          log "instance state is \"#{state}\"..." if DEBUG
          return waitForInstanceToBecomeReady() if state isnt 'running'

          res.publicIpAddress = data.Reservations[0].Instances[0].PublicIpAddress
          res.publicDnsName = data.Reservations[0].Instances[0].PublicDnsName
          res.privateIpAddress = data.Reservations[0].Instances[0].PrivateIpAddress

          Aws.jsonCli """
          aws ec2 create-tags \
            --region #{locals.aws_region} \
            --resource #{res.instanceId} \
            --tag Key=Name,Value=#{name} \
            ;
          """, (err, data) ->
            cb res
      waitForInstanceToBecomeReady()

  destroyInstance: (locals, cb) ->
    Aws.jsonCli """
    aws ec2 terminate-instances \
      --region #{locals.aws_region} \
      --instance-id #{locals.aws_instance_id} \
      ;
    """, (err, data) ->
      throw err if err
      cb()

