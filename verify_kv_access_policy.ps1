# Script to verify and update Key Vault access policy
param (
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string] $KeyVaultName
)

try {
    Write-Host "Verifying Key Vault access policy for $KeyVaultName..."

    # Get current user/service principal context
    $currentContext = Get-AzContext
    $currentUser = Get-AzADUser -SignedIn -ErrorAction SilentlyContinue
    
    if ($null -eq $currentUser) {
        Write-Host "Running as service principal. Getting service principal ID..."
        $servicePrincipalId = (Get-AzADServicePrincipal -ApplicationId $currentContext.Account.Id).Id
        $objectId = $servicePrincipalId
        Write-Host "Service Principal Object ID: $objectId"
    } else {
        $objectId = $currentUser.Id
        Write-Host "Current User Object ID: $objectId"
    }

    # Get the Key Vault
    $keyVault = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName
    if ($null -eq $keyVault) {
        throw "Key Vault '$KeyVaultName' not found in resource group '$ResourceGroupName'"
    }

    # Check if the current identity has the necessary permissions
    $accessPolicy = $keyVault.AccessPolicies | Where-Object { $_.ObjectId -eq $objectId }
    
    if ($null -eq $accessPolicy) {
        Write-Host "No access policy found for current identity. Adding access policy..."
        
        # Set access policy for the current identity
        Set-AzKeyVaultAccessPolicy -ResourceGroupName $ResourceGroupName `
                                  -VaultName $KeyVaultName `
                                  -ObjectId $objectId `
                                  -PermissionsToSecrets Get, List, Set, Delete `
                                  -PermissionsToKeys Get, List, Create, Delete, Update `
                                  -PermissionsToCertificates Get, List, Create, Delete
        
        Write-Host "Access policy added successfully"
    } else {
        # Check if the access policy has the necessary permissions
        $secretPermissions = $accessPolicy.PermissionsToSecrets
        $requiredSecretPermissions = @("Get", "List", "Set", "Delete")
        $missingPermissions = $requiredSecretPermissions | Where-Object { $_ -notin $secretPermissions }
        
        if ($missingPermissions.Count -gt 0) {
            Write-Host "Access policy found but missing permissions: $($missingPermissions -join ', '). Updating access policy..."
            
            # Get existing permissions and add missing ones
            $updatedSecretPermissions = $secretPermissions + $missingPermissions | Select-Object -Unique
            
            # Update access policy
            Set-AzKeyVaultAccessPolicy -ResourceGroupName $ResourceGroupName `
                                      -VaultName $KeyVaultName `
                                      -ObjectId $objectId `
                                      -PermissionsToSecrets $updatedSecretPermissions
            
            Write-Host "Access policy updated successfully"
        } else {
            Write-Host "Access policy already has the necessary permissions"
        }
    }

    Write-Host "Key Vault access policy verification completed successfully"
    return $true
}
catch {
    $errorMessage = $_.Exception.Message
    Write-Error "Error during access policy verification: $errorMessage"
    Write-Error $_.Exception
    throw $_.Exception
}