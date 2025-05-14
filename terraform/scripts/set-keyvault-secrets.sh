#!/bin/bash

# Script to set Key Vault secrets for VM credentials
# Takes 3 parameters: Key Vault name, VM username, VM password

# Check if all required parameters are provided
if [ $# -ne 3 ]; then
    echo "Error: Insufficient parameters"
    echo "Usage: $0 <key-vault-name> <vm-username> <vm-password>"
    exit 1
fi

KEY_VAULT_NAME=$1
VM_USERNAME=$2
VM_PASSWORD=$3

echo "Setting VM credentials in Key Vault: $KEY_VAULT_NAME"

# Set username secret
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "vm-admin-username" --value "$VM_USERNAME" --output none
if [ $? -ne 0 ]; then
    echo "Error: Failed to set username secret in Key Vault"
    exit 1
fi
echo "Username secret set successfully"

# Set password secret
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "vm-admin-password" --value "$VM_PASSWORD" --output none
if [ $? -ne 0 ]; then
    echo "Error: Failed to set password secret in Key Vault"
    exit 1
fi
echo "Password secret set successfully"

echo "VM credentials stored successfully in Key Vault"
exit 0