param(
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$ObjectId = "ddddd-ddddd-ddddd-ddddd-ddddd"
)

Write-Host "Setting Key Vault policy for $KeyVaultName in resource group $ResourceGroupName"

# When running in Azure DevOps with a service connection, Az PowerShell is already authenticated
# No need to run Connect-AzAccount explicitly

try {
    # Method 1: Using Az PowerShell cmdlets with bypass validation flag
    Write-Host "Setting access policy using Az PowerShell cmdlets with BypassObjectIdValidation..."
    Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName `
                              -ResourceGroupName $ResourceGroupName `
                              -ObjectId $ObjectId `
                              -PermissionsToKeys all `
                              -PermissionsToSecrets all `
                              -BypassObjectIdValidation
    
    Write-Host "Access policy set successfully using Az PowerShell!"
}
catch {
    Write-Host "Error using Az PowerShell method: $_"
    
    try {
        # Method 2: Use Az CLI through Azure PowerShell's Invoke-AzCli
        Write-Host "Trying to use Az CLI through Invoke-AzCli cmdlet..."
        
        # Define the Az CLI command with added secret permissions
        $cliCommand = "keyvault set-policy --name $KeyVaultName --object-id $ObjectId --key-permissions all --secret-permissions all --resource-group $ResourceGroupName"
        
        # Execute using Invoke-AzCli which preserves the authentication context
        $azCliResult = & cmd /c "az $cliCommand"
        Write-Host "Az CLI command executed. Result: $azCliResult"
        
        if ($LASTEXITCODE -ne 0) {
            throw "Az CLI command failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Host "Error using Az CLI method as well: $_"
        
        # Method 3: Last resort - REST API direct call
        Write-Host "Attempting direct REST API call to set KeyVault policy..."
        try {
            # Get access token for Azure Resource Manager
            $accessToken = (Get-AzAccessToken -ResourceUrl "https://management.azure.com/").Token
            
            # Get subscription ID
            $subscriptionId = (Get-AzContext).Subscription.Id
            
            # Build URL for REST API
            $apiUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$KeyVaultName/accessPolicies/add?api-version=2022-07-01"
            
            # Build request body
            $requestBody = @{
                properties = @{
                    accessPolicies = @(
                        @{
                            tenantId = (Get-AzContext).Tenant.Id
                            objectId = $ObjectId
                            permissions = @{
                                keys = @("all")
                                secrets = @("all")
                            }
                        }
                    )
                }
            } | ConvertTo-Json -Depth 10
            
            Write-Host "Calling REST API at $apiUrl"
            
            # Make REST API call
            $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $requestBody -ContentType "application/json" -Headers @{
                "Authorization" = "Bearer $accessToken"
            }
            
            Write-Host "REST API call successful"
        }
        catch {
            Write-Host "REST API call failed as well: $_"
            throw "Failed to set Key Vault access policy using all available methods."
        }
    }
}

Write-Host "Key Vault access policy for $ObjectId update completed!"