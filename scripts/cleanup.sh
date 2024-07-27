#!/bin/bash

# List all Terraform-managed resources
terraform state list | tee terraform_resources.txt

# Loop through each resource and destroy it
while IFS= read -r resource
do
  echo "Destroying $resource..."
  terraform destroy -target="$resource" -auto-approve
done < terraform_resources.txt

# Optionally, delete the Terraform state files if you want to start fresh
# rm terraform.tfstate terraform.tfstate.backup

