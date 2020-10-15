provider "aws" {
  profile = "HSTRepro_Sandbox"
  region  = "us-east-1"
}

resource "aws_launch_template" "hstdp" {
  description             = "Template for cluster worker nodes updated to limit stopped container lifespan"
  ebs_optimized           = "false"
  image_id                = "ami-07a63940735aebd38" # this is an amazon ECS community AMI
  key_name                = var.keypair
  tags                    = {
    "Name"         = "calcloud-hst-worker"
    "calcloud-hst" = "calcloud-hst-worker"
  }
  user_data               = "Q29udGVudC1UeXBlOiBtdWx0aXBhcnQvbWl4ZWQ7IGJvdW5kYXJ5PSI9PUJPVU5EQVJZPT0iIApNSU1FLVZlcnNpb246IDEuMCAKCi0tPT1CT1VOREFSWT09Ck1JTUUtVmVyc2lvbjogMS4wIApDb250ZW50LVR5cGU6IHRleHQveC1zaGVsbHNjcmlwdDsgY2hhcnNldD0idXMtYXNjaWkiCgojIS9iaW4vYmFzaAoKZWNobyBFQ1NfRU5HSU5FX1RBU0tfQ0xFQU5VUF9XQUlUX0RVUkFUSU9OPTFtPj4vZXRjL2Vjcy9lY3MuY29uZmlnIAoKeXVtIHVwZGF0ZSAteQoKLS09PUJPVU5EQVJZPT0tLQ=="
  vpc_security_group_ids  = [
        aws_security_group.batchsg.id,
  ]
  block_device_mappings {
    device_name = "/dev/xvda"

  ebs {
    delete_on_termination = "true"
    encrypted             = "false"
    iops                  = 0
    volume_size           = 150
    volume_type           = "gp2"
            }
  }
  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance_role.arn
  }
  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      "Name" = "calcloud-hst-worker"
      "calcloud-hst" = "calcloud-hst-worker"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      "Name" = "calcloud-hst-worker"
      "calcloud-hst" = "calcloud-hst-worker"
    }
  }
}

resource "aws_batch_job_queue" "batch_queue" {
  compute_environments = [
    aws_batch_compute_environment.calcloud.arn
  ]
  name = "calcloud-hst-queue"
  priority = 10
  state = "ENABLED"
  
}

resource "aws_batch_compute_environment" "calcloud" {
  type = "MANAGED"
  service_role = aws_iam_role.aws_batch_service_role.arn
  depends_on = [
    aws_iam_role_policy_attachment.aws_batch_service_role,
  ]

  compute_resources {
    allocation_strategy = "BEST_FIT"
    ec2_key_pair = var.keypair
    instance_role = aws_iam_instance_profile.ecs_instance_role.arn
    type = "EC2"
    bid_percentage = 0
    tags = {}
    subnets             = [aws_subnet.batch_sn.id]
    security_group_ids  = [
      aws_security_group.batchsg.id,
    ]
    instance_type = [
      "m5.large",
      "m5.xlarge",
    ]
    max_vcpus = 32
    min_vcpus = 0
    desired_vcpus = 0

    launch_template {
      launch_template_id = aws_launch_template.hstdp.id
    }
  }
  lifecycle { ignore_changes = [compute_resources.0.desired_vcpus] }
}

resource "aws_ecr_repository" "caldp_ecr" {
  name                 = "caldp"
}

data "aws_ecr_image" "caldp_latest" {
  repository_name = "${aws_ecr_repository.caldp_ecr.name}"
  image_tag = var.image_tag
}

resource "aws_batch_job_definition" "calcloud" {
  name                 = "calcloud-hst-caldp-job-definition"
  type                 = "container"
  container_properties = <<CONTAINER_PROPERTIES
  { 
    "command": ["Ref::command", "Ref::s3_output_path", "Ref::dataset"],
    "environment": [],
    "image": "${aws_ecr_repository.caldp_ecr.repository_url}:${data.aws_ecr_image.caldp_latest.image_tag}",
    "jobRoleArn": "${aws_iam_role.batch_job_role.arn}",
    "memory": 2560,
    "mountPoints": [],
    "resourceRequirements": [],
    "ulimits": [],
    "vcpus": 1,
    "volumes": []
  }
  CONTAINER_PROPERTIES

  parameters = {
    "command" = "caldp-process-aws"
    "dataset" = "j8cb010b0"
    "s3_output_path" = "s3://${aws_s3_bucket.calcloud.bucket}"
  }  

  depends_on = [
    aws_iam_role_policy_attachment.aws_batch_service_role
  ]
}

resource "aws_s3_bucket" "calcloud" {
  bucket = "calcloud-hst-pipeline-outputs-sandbox"
  tags = {
    "CALCLOUD" = "calcloud-hst-pipeline-outputs"
    "Name"     = "calcloud-hst-pipeline-outputs"
  }
}

