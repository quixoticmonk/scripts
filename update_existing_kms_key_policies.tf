provider "aws" {
  region = var.aws_region
}

provider "awscc" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Extract all KMS keys using AWSCC provider
data "awscc_kms_keys" "all_keys" {}

# Extract individual key details using AWSCC provider
data "awscc_kms_key" "key_details" {
  for_each = toset(data.awscc_kms_keys.all_keys.ids)
  id       = each.value
}

# Get key manager information using AWS provider
data "aws_kms_key" "key_manager_info" {
  for_each = toset(data.awscc_kms_keys.all_keys.ids)
  key_id   = each.value
}

# Local values for processing
locals {
  account_id = data.aws_caller_identity.current.account_id
  
  # Filter customer-managed keys only
  # Key distinction: customer-managed keys have key_manager = "CUSTOMER"
  # AWS-managed keys have key_manager = "AWS"
  customer_managed_keys = {
    for key_id in data.awscc_kms_keys.all_keys.ids : key_id => {
      original_policy = try(jsondecode(data.awscc_kms_key.key_details[key_id].key_policy), null)
      awscc_key_info  = data.awscc_kms_key.key_details[key_id]
      aws_key_info    = data.aws_kms_key.key_manager_info[key_id]
    } if can(jsondecode(data.awscc_kms_key.key_details[key_id].key_policy)) && 
         try(data.awscc_kms_key.key_details[key_id].origin, "") == "AWS_KMS" &&
         try(data.awscc_kms_key.key_details[key_id].enabled, false) == true &&
         try(data.aws_kms_key.key_manager_info[key_id].key_manager, "") == "CUSTOMER"
  }
  
  # Administrator policy statement to add
  admin_policy_statement = {
    Sid    = "AllowAccountAdministration"
    Effect = "Allow"
    Principal = {
      AWS = "arn:aws:iam::${local.account_id}:root"
    }
    Action = [
      "kms:*"
    ]
    Resource = "*"
    Condition = {
      StringEquals = {
        "kms:ViaService" = [
          "*.${data.aws_region.current.name}.amazonaws.com"
        ]
      }
    }
  }
  
  # Generate updated policies for each customer-managed key
  updated_policies = {
    for key_id, key_info in local.customer_managed_keys : key_id => {
      original_policy = key_info.original_policy
      updated_policy = {
        Version = try(key_info.original_policy.Version, "2012-10-17")
        Statement = concat(
          try(key_info.original_policy.Statement, []),
          [local.admin_policy_statement]
        )
      }
    }
  }
}

# Update KMS key policies using aws_kms_key_policy resource
resource "aws_kms_key_policy" "updated_policies" {
  for_each = local.updated_policies
  
  key_id = each.key
  policy = jsonencode(each.value.updated_policy)
}


