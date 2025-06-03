#!/bin/bash

# Script to set up GitHub OIDC provider and create a role for GitHub Actions
# This script sets up an Identity provider for GitHub on the target AWS account
# and creates a role called "github-role" that allows the 
# repository "quixoticmonk/terraform-aws-glue" to assume it

# Display usage information if no arguments provided
if [ "$#" -gt 0 ] && [ "$1" == "--help" ]; then
    echo "Usage: $0"
    echo ""
    echo "This script sets up a GitHub OIDC provider in AWS and creates a role"
    echo "called 'github-role' that can be assumed by the"
    echo "'quixoticmonk/terraform-aws-glue' GitHub repository."
    echo ""
    echo "Required files:"
    echo "  - policy.json: IAM policy to attach to the role"
    echo "  - policy2.json: Additional IAM policy to attach to the role"
    echo "  - perm1.json: Permissions boundary to attach to the role"
    echo "  - perm2.json: Standalone permissions boundary (not attached to any role)"
    echo ""
    echo "The script will prompt for the following values to replace placeholders:"
    echo "  - AWS Account ID"
    echo "  - Product ID"
    echo "  - Product Name"
    echo "  - AWS Region"
    echo ""
    echo "Make sure you have the AWS CLI installed and configured with appropriate credentials."
    exit 0
fi

set -e

# Prompt for placeholder values
read -p "Enter AWS Account ID: " ACCOUNT_ID
read -p "Enter Product ID: " PRODUCT_ID
read -p "Enter Product Name: " PRODUCT_NAME
read -p "Enter AWS Region: " REGION

# Function to replace placeholders in JSON files
replace_placeholders() {
    local file=$1
    if [ -f "$file" ]; then
        echo "Replacing placeholders in $file..."
        sed -i.bak "s/ACCOUNT_ID/$ACCOUNT_ID/g" "$file"
        sed -i.bak "s/PRODUCT_ID/$PRODUCT_ID/g" "$file"
        sed -i.bak "s/PRODUCT_NAME/$PRODUCT_NAME/g" "$file"
        sed -i.bak "s/REGION/$REGION/g" "$file"
        rm -f "${file}.bak"
    fi
}

# Replace placeholders in all policy files
replace_placeholders "policy.json"
replace_placeholders "policy2.json"
replace_placeholders "perm1.json"
replace_placeholders "perm2.json"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

echo "Setting up GitHub OIDC provider..."

# Create the GitHub OIDC provider
PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
    --query 'OpenIDConnectProviderArn' \
    --output text)

echo "Created GitHub OIDC provider with ARN: $PROVIDER_ARN"

# Create trust policy for the role
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "$PROVIDER_ARN"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:quixoticmonk/terraform-aws-glue:*"
        }
      }
    }
  ]
}
EOF

echo "Creating role github-role..."

# Check if perm1.json exists to use as permissions boundary
if [ -f "perm1.json" ]; then
    echo "Using perm1.json as permissions boundary for the role..."
    PERM_BOUNDARY_ARN=$(aws iam create-policy \
        --policy-name git-provisioning-boundary \
        --policy-document file://perm1.json \
        --query 'Policy.Arn' \
        --output text)
    
    # Create the role with the trust policy and permissions boundary
    ROLE_ARN=$(aws iam create-role \
        --role-name github-role \
        --assume-role-policy-document file://trust-policy.json \
        --permissions-boundary $PERM_BOUNDARY_ARN \
        --query 'Role.Arn' \
        --output text)
    
    echo "Applied permissions boundary: $PERM_BOUNDARY_ARN"
else
    echo "Warning: perm1.json not found. Creating role without permissions boundary."
    # Create the role with the trust policy
    ROLE_ARN=$(aws iam create-role \
        --role-name github-role \
        --assume-role-policy-document file://trust-policy.json \
        --query 'Role.Arn' \
        --output text)
fi

echo "Created role with ARN: $ROLE_ARN"

# Check if policy files exist and attach them
if [ -f "policy.json" ]; then
    echo "Attaching policy from policy.json..."
    POLICY_ARN=$(aws iam create-policy \
        --policy-name git-provisioning-policy-1 \
        --policy-document file://policy.json \
        --query 'Policy.Arn' \
        --output text)
    
    aws iam attach-role-policy \
        --role-name github-role \
        --policy-arn $POLICY_ARN
    
    echo "Attached policy: $POLICY_ARN"
fi

if [ -f "policy2.json" ]; then
    echo "Attaching policy from policy2.json..."
    POLICY_ARN2=$(aws iam create-policy \
        --policy-name git-provisioning-policy-2 \
        --policy-document file://policy2.json \
        --query 'Policy.Arn' \
        --output text)
    
    aws iam attach-role-policy \
        --role-name github-role \
        --policy-arn $POLICY_ARN2
    
    echo "Attached policy: $POLICY_ARN2"
fi

# Create perm2.json permissions boundary without attaching it to any role
if [ -f "perm2.json" ]; then
    echo "Creating permissions boundary from perm2.json (not attached to any role)..."
    PERM2_BOUNDARY_ARN=$(aws iam create-policy \
        --policy-name standalone-permissions-boundary \
        --policy-document file://perm2.json \
        --query 'Policy.Arn' \
        --output text)
    
    echo "Created standalone permissions boundary: $PERM2_BOUNDARY_ARN"
else
    echo "Warning: perm2.json not found. Skipping creation of standalone permissions boundary."
fi

echo "Setup complete!"
echo "GitHub OIDC provider and github-role have been created."
echo "The role is configured to be assumed by the repository: quixoticmonk/terraform-aws-glue"

# Clean up temporary files
rm -f trust-policy.json

echo "Note: Make sure to create policy.json, policy2.json, perm1.json, and perm2.json with the required permissions before running this script."
