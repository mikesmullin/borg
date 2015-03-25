delay = (s,f) -> setTimeout f, s
AWS = require 'aws-sdk'

# interfaces with aws api; your key and secret
# must be configured via env vars or ~/.aws/credentials file
# by you manually before any of this will work.
# see: http://docs.aws.amazon.com/AWSJavaScriptSDK/guide/node-configuring.html

module.exports = (log) -> AwsWrapper =
  ec2Api: (cmd, params, cb) ->
    log "API Request:\nAWS.EC2.#{cmd}(#{JSON.stringify params, null, 2})\n" if DEBUG
    if params.Region?
      ec2 = new AWS.EC2 region: params.Region
      delete params.Region
    else
      ec2 = new AWS.EC2()
    ec2[cmd] params, (err, data) ->
      if err isnt null
        log 'APIClient Error: '+ err
        throw err
      log 'data: '+ JSON.stringify(data, null, 2) if DEBUG
      cb data

  createInstance: (name, locals, instance_cb, done_cb) ->
    log "creating one #{name} instance..."
    res = {}

    makeVolume = (cb) ->
      return cb() unless locals.aws_ebs_volume

      # size = size of the volume in GBs
      # type: The volume type. This can be gp2 for General Purpose (SSD)
      # volumes, io1 for Provisioned IOPS (SSD) volumes, or standard for
      # Magnetic volumes.
      AwsWrapper.ec2Api 'createVolume',
        Region: locals.aws_region
        AvailabilityZone: locals.aws_zone
        Size: locals.aws_ebs_volume.size
        VolumeType: locals.aws_ebs_volume.type
        Iops: locals.aws_ebs_volume?.iops
      , (data) ->
        locals.aws_ebs_volume.id = data.VolumeId
        cb()

    makeInstance = (cb) ->
      params =
        Region: locals.aws_region
        ImageId: locals.aws_image
        MinCount: 1
        MaxCount: 1
        InstanceType: locals.aws_size
        KeyName: locals.aws_key
        BlockDeviceMappings: [
          { DeviceName: '/dev/xvdb', VirtualName: 'ephemeral0' }
          { DeviceName: '/dev/xvdc', VirtualName: 'ephemeral1' }
          { DeviceName: '/dev/xvdd', VirtualName: 'ephemeral2' }
          { DeviceName: '/dev/xvde', VirtualName: 'ephemeral3' }
        ]

      if locals.aws_zone
        params.Placement =
          AvailabilityZone: locals.aws_zone
          Tenancy: locals.aws_tenancy or 'default'
      if locals.aws_ebs_volume?.optimized
        params.EbsOptimized = locals.aws_ebs_volume.optimized
      if locals.aws_security_groups
        params.SecurityGroups = locals.aws_security_groups

      if locals.aws_subnet or
        locals.aws_associate_public_ip or
        locals.aws_security_group_ids
          params.NetworkInterfaces = [{ DeviceIndex: 0 }]
      if locals.aws_subnet
        params.NetworkInterfaces[0].SubnetId = locals.aws_subnet
      if locals.aws_associate_public_ip
        params.NetworkInterfaces[0].AssociatePublicIpAddress = locals.aws_associate_public_ip
      if locals.aws_security_group_ids
        params.NetworkInterfaces[0].Groups = locals.aws_security_group_ids

      AwsWrapper.ec2Api 'runInstances', params, (data) ->
        instance_cb res.instanceId = data.Instances[0].InstanceId
        cb()

    waitForInstanceToBecomeReady = -> delay 4000, ->
      AwsWrapper.ec2Api 'describeInstances',
        Region: locals.aws_region
        InstanceIds: [ res.instanceId ]
      , (data) ->
        state = data.Reservations[0].Instances[0].State.Name
        log "instance state is \"#{state}\"..." if DEBUG
        return waitForInstanceToBecomeReady() if state isnt 'running'

        res.publicIpAddress = data.Reservations[0].Instances[0].PublicIpAddress
        res.publicDnsName = data.Reservations[0].Instances[0].PublicDnsName
        res.privateIpAddress = data.Reservations[0].Instances[0].PrivateIpAddress

        AwsWrapper.ec2Api 'createTags',
          Region: locals.aws_region
          Resources: [ res.instanceId ]
          Tags: [{ Key: "Name", Value: name }]
        , (data) ->
          if locals.aws_ebs_volume
            AwsWrapper.ec2Api 'attachVolume',
              Region: locals.aws_region
              Device: '/dev/xvdq'
              InstanceId: res.instanceId
              VolumeId: locals.aws_ebs_volume.id
            , (data) ->
              done_cb res
          else
            done_cb res

    makeVolume ->
      makeInstance ->
        waitForInstanceToBecomeReady()

  destroyInstance: (locals, cb) ->
    AwsWrapper.ec2Api 'terminateInstances',
      Region: locals.aws_region
      InstanceIds: [ locals.aws_instance_id ]
    , (data) ->
      cb()
