exec = require('child_process').exec
delay = (s,f) -> setTimeout f, s

# interfaces with aws cli;
# which is a dependency that must be pre-installed,
# and configured with your aws api key,
# by you manually before any of this will work.

module.exports = (log) -> Aws =
  jsonCli: (cmd, cb) ->
    child = undefined
    cmd = cmd.replace /[\r\n\s]+/g, ' '
    log "AWS CLI Command:\n"+cmd+"\n" if DEBUG
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

  createInstance: (name, locals, instance_cb, done_cb) ->
    log "creating one #{name} instance..."
    res = {}

    makeVolume = (cb) ->
      return cb() unless locals.aws_ebs_volume

      # size = size of the volume in GBs
      # type: The volume type. This can be gp2 for General Purpose (SSD) volumes, io1 for Provisioned IOPS (SSD) volumes, or standard for Magnetic volumes.
      Aws.jsonCli """
      aws ec2 create-volume
        --region #{locals.aws_region}
        --availability-zone #{locals.aws_zone}
        --size #{locals.aws_ebs_volume.size}
        --volume-type #{locals.aws_ebs_volume.type}
        #{if locals.aws_ebs_volume.iops then "--iops #{locals.aws_ebs_volume.iops}" else ''}
      """, (err, data) ->
        throw err if err
        locals.aws_ebs_volume.id = data.VolumeId
        cb()

    makeInstance = (cb) ->
      Aws.jsonCli """
      aws ec2 run-instances
        --region #{locals.aws_region}
        --image-id #{locals.aws_image}
        --count 1
        #{if locals.aws_zone then '--placement=\'{"AvailabilityZone":"'+locals.aws_zone+'","Tenancy":"'+(locals.aws_tenancy or 'default')+'"}\'' else ''}
        --instance-type #{locals.aws_size}
        --key-name #{locals.aws_key}
        #{if locals.aws_security_groups then "--security-groups #{locals.aws_security_groups.join ','}" else ''}
        #{if locals.aws_security_group_ids then "--security-group-ids #{locals.aws_security_group_ids.join ','}" else ''}
        #{if locals.aws_subnet then "--subnet-id #{locals.aws_subnet}" else ''}
        #{if locals.aws_associate_public_ip then "--associate-public-ip-address" else ''}
        #{if locals.aws_ebs_volume?.optimized then "--ebs-optimized" else '--no-ebs-optimized'}
        --block-device-mappings='[
          {"DeviceName":"/dev/xvdb","VirtualName":"ephemeral0"},
          {"DeviceName":"/dev/xvdc","VirtualName":"ephemeral1"},
          {"DeviceName":"/dev/xvdd","VirtualName":"ephemeral2"},
          {"DeviceName":"/dev/xvde","VirtualName":"ephemeral3"}
        ]'
        ;
      """, (err, data) ->
        throw err if err
        instance_cb res.instanceId = data.Instances[0].InstanceId
        cb()

    waitForInstanceToBecomeReady = -> delay 4000, ->
      Aws.jsonCli """
      aws ec2 describe-instances \
        --region #{locals.aws_region} \
        --instance-id #{res.instanceId} \
        ;
      """, (err, data) ->
        throw err if err
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
          throw err if err
          if locals.aws_ebs_volume
            Aws.jsonCli """
            aws ec2 attach-volume
              --region #{locals.aws_region}
              --volume #{locals.aws_ebs_volume.id}
              --instance #{res.instanceId}
              --device /dev/xvdq
            """, (err, data) ->
              done_cb res
          else
            done_cb res

    makeVolume ->
      makeInstance ->
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

