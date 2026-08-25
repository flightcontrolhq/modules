################################################################################
# Host role
#
# The identity every sandbox host runs as. It holds exactly what the host agent
# needs to boot, fetch its own M2M credential, page snapshot chunks, ship logs,
# pull base images and — in vpc-ip mode — hand VPC IPs to sandboxes. Nothing a
# guest gets ever comes from this role: guest credentials are minted by the
# broker and delivered through MMDS.
################################################################################

resource "aws_iam_role" "host" {
  name        = "${local.name_prefix}-host"
  description = "Sandbox host identity for pool ${var.pool_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, { Name = "${local.name_prefix}-host" })
}

resource "aws_iam_instance_profile" "host" {
  name = "${local.name_prefix}-host"
  role = aws_iam_role.host.name

  tags = merge(local.tags, { Name = "${local.name_prefix}-host" })
}

# Session Manager, so an operator can get a shell on a host without SSH keys,
# a bastion or an inbound port.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  count = var.attach_ssm_managed_policy ? 1 : 0

  role       = aws_iam_role.host.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

################################################################################
# Host policy
################################################################################

resource "aws_iam_role_policy" "host" {
  name = "${local.name_prefix}-host"
  role = aws_iam_role.host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # --- the host's own WorkOS M2M credential ---------------------------
      # The reconciler writes /ravion/sandboxes/<pool>/hosts/<instanceId>/m2m
      # as a SecureString before the host boots, tagged
      # `ravion:instance-arn = <that instance's ARN>`.
      #
      # IAM cannot template the calling instance's id into a resource ARN, so
      # the resource here is necessarily the whole pool prefix. What narrows
      # it to one parameter is the tag condition: `ssm:ResourceTag` is
      # evaluated against the parameter being read, and `${ec2:SourceInstanceARN}`
      # is the ARN of the instance whose profile signed the request. The two
      # are equal for exactly one parameter per host. A parameter that is
      # missing the tag — or was written by anything other than the
      # reconciler — fails the condition, so this fails closed.
      #
      # `ssm:GetParameters` (plural) is deliberately absent: the host agent
      # reads with GetParameter, and every path-enumerating call
      # (GetParametersByPath, DescribeParameters) is excluded everywhere.
      {
        Sid    = "ReadOwnHostCredential"
        Effect = "Allow"
        Action = ["ssm:GetParameter"]
        Resource = [
          "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter${local.ssm_param_prefix}/*",
        ]
        Condition = {
          StringEquals = { "ssm:ResourceTag/${local.host_instance_arn_tag}" = "$${ec2:SourceInstanceARN}" }
          ArnLike      = { "ec2:SourceInstanceARN" = local.host_instance_arn_pattern }
        }
      },
      # SecureString decryption, pinned to SSM as the calling service so the
      # key cannot be used to read anything else encrypted with it.
      {
        Sid      = "DecryptHostCredential"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "arn:${local.partition}:kms:${local.region}:${local.account_id}:key/*"
        Condition = {
          StringEquals = { "kms:ViaService" = "ssm.${local.region}.amazonaws.com" }
        }
      },
      # --- snapshot chunk store -------------------------------------------
      {
        Sid    = "SnapshotObjectsReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:PutObject",
          "s3:PutObjectTagging",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
        ]
        Resource = "${aws_s3_bucket.snapshots.arn}/*"
      },
      {
        Sid      = "SnapshotBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.snapshots.arn
      },
      # --- logs ------------------------------------------------------------
      {
        Sid    = "WriteLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = [
          aws_cloudwatch_log_group.host.arn,
          "${aws_cloudwatch_log_group.host.arn}:log-stream:*",
          aws_cloudwatch_log_group.sandbox.arn,
          "${aws_cloudwatch_log_group.sandbox.arn}:log-stream:*",
        ]
      },
      # --- base images from public ECR --------------------------------------
      # Both actions are account-wide by API design: they mint a bearer token
      # and grant no repository access of their own.
      {
        Sid      = "PullPublicBaseImages"
        Effect   = "Allow"
        Action   = ["ecr-public:GetAuthorizationToken", "sts:GetServiceBearerToken"]
        Resource = "*"
      },
    ]
  })
}

# --- vpc-ip mode: hand VPC IPs to sandboxes ---------------------------------
# Scoped by tag: the launch template tags every ENI it creates with
# ravion:pool, so this role can only reshape IPs on ENIs belonging to its own
# pool. IAM has no way to say "the ENI attached to me", so the pool tag plus
# the instance-credentials condition is the floor. Cross-host reach within one
# pool is the residual, and every host in a pool is already the same trust
# domain.
resource "aws_iam_role_policy" "host_vpc_ip" {
  count = local.vpc_ip_mode ? 1 : 0

  name = "${local.name_prefix}-host-vpc-ip"
  role = aws_iam_role.host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageOwnPoolEniAddresses"
        Effect = "Allow"
        Action = concat(
          [
            "ec2:AssignPrivateIpAddresses",
            "ec2:UnassignPrivateIpAddresses",
          ],
          var.ipv6_enabled ? [
            "ec2:AssignIpv6Addresses",
            "ec2:UnassignIpv6Addresses",
          ] : []
        )
        Resource = "arn:${local.partition}:ec2:${local.region}:${local.account_id}:network-interface/*"
        Condition = {
          StringEquals = { "ec2:ResourceTag/ravion:pool" = var.pool_id }
          ArnLike      = { "ec2:SourceInstanceARN" = local.host_instance_arn_pattern }
        }
      },
      # Describe* takes no resource-level scoping; the instance-credentials
      # condition is all that can be said about it.
      #
      # DescribeSubnets is here because prefix delegation is not enough on its
      # own: a delegated address is handed to a guest with the SUBNET's mask and
      # gateway, and `EC2ENIClient.HostENIs` learns both from the subnet the
      # host's ENI sits in. Without it a vpc-ip host allocates addresses it
      # cannot configure.
      {
        Sid      = "DescribeOwnNetworkContext"
        Effect   = "Allow"
        Action   = ["ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets"]
        Resource = "*"
        Condition = {
          ArnLike = { "ec2:SourceInstanceARN" = local.host_instance_arn_pattern }
        }
      },
    ]
  })
}
