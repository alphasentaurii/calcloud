module "calcloud_lambda_refresh_cache_submit" {
  source = "terraform-aws-modules/lambda/aws"
  version = "~> 1.43.0"

  function_name = "calcloud-fileshare-refresh_cache_submit${local.environment}"
  description   = "submits refresh cache operations"
  # the path is relative to the path inside the lambda env, not in the local filesystem. 
  handler       = "refresh_cache_submit.lambda_handler"
  runtime       = "python3.6"
  publish       = false
  timeout       = 900
  cloudwatch_logs_retention_in_days = 30

  source_path = [
    {
      # this is the lambda itself. The code in path will be placed directly into the lambda execution path
      path = "${path.module}/../lambda/refreshCacheSubmit"
      pip_requirements = false
    },
    {
      # calcloud for the package. We don't need to install boto3 and whatnot so we leave out the pip requirements
      # in the zip it will be installed into a directory called calcloud
      path = "${path.module}/../calcloud"
      prefix_in_zip = "calcloud"
      pip_requirements = false
    }
  ]

  store_on_s3 = true
  s3_bucket   = aws_s3_bucket.calcloud_lambda_envs.id

  # ensures that terraform doesn't try to mess with IAM
  create_role = false
  attach_cloudwatch_logs_policy = false
  attach_dead_letter_policy = false
  attach_network_policy = false
  attach_tracing_policy = false
  attach_async_event_policy = false
  # existing role for the lambda
  # will need to parametrize when ITSD takes over role creation. 
  # for now this role was created by hand in the console, it is not terraform managed
  lambda_role = data.aws_ssm_parameter.lambda_refreshCacheSubmit_role.value

  environment_variables = {
    # comma delimited list of job queues, because batch can only list jobs per queue
    FILESHARE=data.aws_ssm_parameter.file_share_arn.value
  }

  tags = {
    Name = "calcloud-fileshare-refresh_cache_submits${local.environment}"
  }
}

resource "aws_cloudwatch_event_rule" "refresh_cache_schedule" {
  name                = "refresh-cache-scheduler"
  description         = "Fires every five minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "refresh_cache_submit" {
  rule      = aws_cloudwatch_event_rule.refresh_cache_schedule.name
  target_id = "lambda"
  arn       = module.calcloud_lambda_refresh_cache_submit.this_lambda_function_arn
}

resource "aws_lambda_permission" "refresh_cache_submit" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = module.calcloud_lambda_refresh_cache_submit.this_lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.refresh_cache_schedule.arn
}