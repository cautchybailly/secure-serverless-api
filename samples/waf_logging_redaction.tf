resource "aws_wafv2_web_acl_logging_configuration" "logging" {
  log_destination_configs = [trimsuffix(aws_cloudwatch_log_group.waf_logs.arn, ":*")]
  resource_arn            = aws_wafv2_web_acl.waf.arn

  ##########################################################
  # Redaction
  #
  # WAF logs the full request. Without this, every Cognito
  # access token callers send lands in CloudWatch in plaintext
  # with 7-day retention - a credential store nobody intended
  # to build.
  ##########################################################

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.waf_log_delivery]
}
