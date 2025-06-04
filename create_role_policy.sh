#!/bin/bash

# Script to set up GitHub OIDC provider and create a role for GitHub Actions
# This script sets up an Identity provider for GitHub on the target AWS account
# and creates a role called "git-provisioning-agent-role" that allows the 
# repository "quixoticmonk/terraform-aws-glue" to assume it

# Display usage information if no arguments provided
if [ "$#" -gt 0 ] && [ "$1" == "--help" ]; then
    echo "Usage: $0"
    echo ""
    echo "This script sets up a GitHub OIDC provider in AWS and creates a role"
    echo "called 'role-PRODUCT_NAME-PRODUCT_ID-glue-git-provisioningagent' that can be assumed by the"
    echo "GitHub repository you specify."
    echo ""
    echo "Required files:"
    echo "  - policya.json: IAM policy to attach to the role"
    echo "  - policyb.json: Additional IAM policy to attach to the role"
    echo "  - policyc.json: Additional IAM policy to attach to the role"
    echo "  - policyd.json: Additional IAM policy to attach to the role"
    echo "  - perm1.json: Permissions boundary to attach to the role"
    echo "  - perm2.json: Standalone permissions boundary (not attached to any role)"
    echo ""
    echo "The script will prompt for the following values to replace placeholders:"
    echo "  - AWS Account ID"
    echo "  - Product ID"
    echo "  - Product Name"
    echo "  - AWS Region (defaults to us-east-1)"
    echo "  - GitHub Repository"
    echo ""
    echo "Make sure you have the AWS CLI installed and configured with appropriate credentials."
    exit 0
fi

set -e

# Prompt for placeholder values
read -p "Enter AWS Account ID: " ACCOUNT_ID
read -p "Enter Product ID: " PRODUCT_ID
read -p "Enter Product Name: " PRODUCT_NAME
read -p "Enter GitHub Repository (e.g., username/repo): " GITHUB_REPO

# Set default region if not provided
REGION=${REGION:-"us-east-1"}
echo "Using AWS Region: $REGION"

# Function to create temporary JSON files with placeholders replaced
create_temp_json() {
    local file=$1
    local temp_file="temp_${file}"
    if [ -f "$file" ]; then
        echo "Creating temporary file with replaced placeholders: $temp_file"
        cp "$file" "$temp_file"
        sed -i.bak "s/ACCOUNT_ID/$ACCOUNT_ID/g" "$temp_file"
        sed -i.bak "s/PRODUCT_ID/$PRODUCT_ID/g" "$temp_file"
        sed -i.bak "s/PRODUCT_NAME/$PRODUCT_NAME/g" "$temp_file"
        sed -i.bak "s/REGION/$REGION/g" "$temp_file"
        rm -f "${temp_file}.bak"
    fi
}

# Create temporary JSON files with placeholders replaced
create_temp_json "policya.json"
create_temp_json "policyb.json"
create_temp_json "policyc.json"
create_temp_json "policyd.json"
create_temp_json "perm1.json"
create_temp_json "perm2.json"

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
          "token.actions.githubusercontent.com:sub": "repo:$GITHUB_REPO:*"
        }
      }
    }
  ]
}
EOF

echo "Creating role role-${PRODUCT_NAME}-${PRODUCT_ID}-glue-git-provisioningagent..."

# Check if temp_perm1.json exists to use as permissions boundary
if [ -f "temp_perm1.json" ]; then
    echo "Using temp_perm1.json as permissions boundary for the role..."
    # Use the filename without extension as the policy name
    local perm1_name=$(basename "perm1.json" .json)
    PERM_BOUNDARY_ARN=$(aws iam create-policy \
        --policy-name "$perm1_name" \
        --policy-document file://temp_perm1.json \
        --tags Key=product_name,Value="$PRODUCT_NAME" Key=product_id,Value="$PRODUCT_ID" Key=ProductName,Value="$PRODUCT_NAME" Key=ProductId,Value="$PRODUCT_ID" \
        --query 'Policy.Arn' \
        --output text)
    
    # Create the role with the trust policy and permissions boundary
    ROLE_ARN=$(aws iam create-role \
        --role-name role-${PRODUCT_NAME}-${PRODUCT_ID}-glue-git-provisioningagent \
        --assume-role-policy-document file://trust-policy.json \
        --permissions-boundary "$PERM_BOUNDARY_ARN" \
        --tags Key=product_name,Value="$PRODUCT_NAME" Key=product_id,Value="$PRODUCT_ID" Key=ProductName,Value="$PRODUCT_NAME" Key=ProductId,Value="$PRODUCT_ID" \
        --query 'Role.Arn' \
        --output text)
    
    echo "Applied permissions boundary: $PERM_BOUNDARY_ARN"
else
    echo "Warning: perm1.json not found. Creating role without permissions boundary."
    # Create the role with the trust policy
    ROLE_ARN=$(aws iam create-role \
        --role-name role-${PRODUCT_NAME}-${PRODUCT_ID}-glue-git-provisioningagent \
        --assume-role-policy-document file://trust-policy.json \
        --tags Key=product_name,Value="$PRODUCT_NAME" Key=product_id,Value="$PRODUCT_ID" Key=ProductName,Value="$PRODUCT_NAME" Key=ProductId,Value="$PRODUCT_ID" \
        --query 'Role.Arn' \
        --output text)
fi

echo "Created role with ARN: $ROLE_ARN"

# Function to create and attach a policy
create_and_attach_policy() {
    local policy_file=$1
    local role_name=$2
    local temp_policy_file="temp_$policy_file"
    
    if [ -f "$temp_policy_file" ]; then
        # Extract policy name from filename (remove .json extension)
        local policy_name=$(basename "$policy_file" .json)
        
        echo "Attaching policy from $temp_policy_file..."
        local policy_arn=$(aws iam create-policy \
            --policy-name "$policy_name" \
            --policy-document "file://$temp_policy_file" \
            --tags Key=product_name,Value="$PRODUCT_NAME" Key=product_id,Value="$PRODUCT_ID" Key=ProductName,Value="$PRODUCT_NAME" Key=ProductId,Value="$PRODUCT_ID" \
            --query 'Policy.Arn' \
            --output text)
        
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn"
        
        echo "Attached policy: $policy_arn"
    fi
}

# Create and attach policies
create_and_attach_policy "policya.json" "role-${PRODUCT_NAME}-${PRODUCT_ID}-glue-git-provisioningagent"
create_and_attach_policy "policyb.json" "role-${PRODUCT_NAME}-${PRODUCT_ID}-glue-git-provisioningagent"
create_and_attach_policy "policyc.json" "role-${PRODUCT_NAME}-${PRODUCT_ID}-glue-git-provisioningagent"
create_and_attach_policy "policyd.json" "role-${PRODUCT_NAME}-${PRODUCT_ID}-glue-git-provisioningagent"

# Create temp_perm2.json permissions boundary without attaching it to any role
if [ -f "temp_perm2.json" ]; then
    echo "Creating permissions boundary from temp_perm2.json (not attached to any role)..."
    # Use the filename without extension as the policy name
    perm2_name=$(basename "perm2.json" .json)
    PERM2_BOUNDARY_ARN=$(aws iam create-policy \
        --policy-name "$perm2_name" \
        --policy-document file://temp_perm2.json \
        --tags Key=product_name,Value="$PRODUCT_NAME" Key=product_id,Value="$PRODUCT_ID" Key=ProductName,Value="$PRODUCT_NAME" Key=ProductId,Value="$PRODUCT_ID" \
        --query 'Policy.Arn' \
        --output text)
    
    echo "Created standalone permissions boundary: $PERM2_BOUNDARY_ARN"
else
    echo "Warning: perm2.json not found. Skipping creation of standalone permissions boundary."
fi

# Create admin policy without attaching it to any role
echo "Creating admin policy with administrator access..."
cat > temp_admin.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }
  ]
}
EOF

ADMIN_POLICY_ARN=$(aws iam create-policy \
    --policy-name "admin-${PRODUCT_NAME}-${PRODUCT_ID}" \
    --policy-document file://temp_admin.json \
    --tags Key=product_name,Value="$PRODUCT_NAME" Key=product_id,Value="$PRODUCT_ID" Key=ProductName,Value="$PRODUCT_NAME" Key=ProductId,Value="$PRODUCT_ID" \
    --query 'Policy.Arn' \
    --output text)

echo "Created standalone admin policy: $ADMIN_POLICY_ARN"

echo "Setup complete!"
echo "GitHub OIDC provider and role-${PRODUCT_NAME}-${PRODUCT_ID}-glue-git-provisioningagent have been created."
echo "The role is configured to be assumed by the repository: $GITHUB_REPO"

# Clean up temporary files
rm -f trust-policy.json
rm -f temp_*.json

echo "Note: Make sure to create policya.json, policyb.json, policyc.json, policyd.json, perm1.json, and perm2.json with the required permissions before running this script."

# Output the ARN of the role as the last step
echo "********************"
echo "Role ARN: $ROLE_ARN"
echo "********************"
