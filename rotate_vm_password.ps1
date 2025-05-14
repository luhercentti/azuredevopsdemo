# PowerShell script to rotate VM admin password and update Key Vault
param (
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string] $VMName,
    
    [Parameter(Mandatory = $true)]
    [string] $KeyVaultName,
    
    [Parameter(Mandatory = $false)]
    [string] $AdminUsernameSecretName = "vm-admin-username",
    
    [Parameter(Mandatory = $false)]
    [string] $AdminPasswordSecretName = "vm-admin-password",
    
    [Parameter(Mandatory = $false)]
    [string] $DefaultAdminUsername = "azureadmin"
)

function Generate-StrongPassword {
    param (
        [int] $Length = 16
    )
    
    # Define character sets
    $uppercaseChars = "ABCDEFGHJKLMNPQRSTUVWXYZ"     # Omitted I, O
    $lowercaseChars = "abcdefghijkmnopqrstuvwxyz"     # Omitted l
    $numberChars = "23456789"                         # Omitted 0, 1
    $specialChars = "!@#$%^&*_-+="
    
    # Create character pool
    $charPool = $uppercaseChars + $lowercaseChars + $numberChars + $specialChars
    
    # Initialize password with at least one character from each set to ensure complexity
    $password = $uppercaseChars[(Get-Random -Maximum $uppercaseChars.Length)] +
                $lowercaseChars[(Get-Random -Maximum $lowercaseChars.Length)] +
                $numberChars[(Get-Random -Maximum $numberChars.Length)] +
                $specialChars[(Get-Random -Maximum $specialChars.Length)]
    
    # Add remaining characters randomly
    for ($i = $password.Length; $i -lt $Length; $i++) {
        $password += $charPool[(Get-Random -Maximum $charPool.Length)]
    }
    
    # Shuffle the password characters
    $passwordArray = $password.ToCharArray()
    $shuffledArray = $passwordArray | Sort-Object { Get-Random }
    $shuffledPassword = -join $shuffledArray
    
    return $shuffledPassword
}

try {
    Write-Host "Starting VM password rotation process..."
    
    # Step 1: Get the VM
    Write-Host "Retrieving VM information for $VMName..."
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
    if ($null -eq $vm) {
        throw "VM '$VMName' not found in resource group '$ResourceGroupName'"
    }
    Write-Host "VM found: $($vm.Name)"
    
    # Step 2: Get the admin username from Key Vault or use default
    Write-Host "Checking for admin username in Key Vault..."
    try {
        $adminUsernameSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AdminUsernameSecretName -ErrorAction SilentlyContinue
        
        if ($null -eq $adminUsernameSecret -or [string]::IsNullOrWhiteSpace($adminUsernameSecret.SecretValueText)) {
            Write-Host "Admin username not found in Key Vault or is empty. Using default: $DefaultAdminUsername"
            $adminUsername = $DefaultAdminUsername
            
            # Set the username in Key Vault
            Write-Host "Saving username '$adminUsername' to Key Vault..."
            $secretValue = ConvertTo-SecureString -String $adminUsername -AsPlainText -Force
            Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AdminUsernameSecretName -SecretValue $secretValue -ErrorAction Stop
            Write-Host "Username saved to Key Vault successfully"
        } else {
            $adminUsername = $adminUsernameSecret.SecretValueText
            Write-Host "Admin username retrieved: $adminUsername"
        }
    } catch {
        Write-Host "Error accessing Key Vault for username. Using default: $DefaultAdminUsername"
        $adminUsername = $DefaultAdminUsername
    }
    
    # Verify username is valid
    if ([string]::IsNullOrWhiteSpace($adminUsername)) {
        Write-Host "Username is still empty after retrieval. Using default: $DefaultAdminUsername"
        $adminUsername = $DefaultAdminUsername
    }
    
    # Step 3: Generate a new strong password
    Write-Host "Generating new strong password..."
    $newPassword = Generate-StrongPassword -Length 20
    Write-Host "New password generated (not displayed for security reasons)"
    $securePassword = ConvertTo-SecureString -String $newPassword -AsPlainText -Force
    
    # Step 4: Update VM with new password using the VM Access Extension
    Write-Host "Updating VM with new password..."
    Write-Host "Setting password for user: '$adminUsername'"
    
    # First, check if VMAccessAgent extension is installed
    $extensions = Get-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -ErrorAction SilentlyContinue
    $vmAccessExt = $extensions | Where-Object { $_.Name -eq "VMAccessAgent" }
    
    if ($vmAccessExt) {
        Write-Host "Removing existing VMAccessAgent extension..."
        Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -Name "VMAccessAgent" -Force | Out-Null
        Write-Host "Existing VMAccessAgent extension removed"
    }
    
    # Create a public settings JSON
    Write-Host "Creating VM Access Extension settings..."
    $publicSettings = @{
        username = $adminUsername
    } | ConvertTo-Json
    
    $protectedSettings = @{
        password = $newPassword
    } | ConvertTo-Json
    
    # Add VM access extension
    Write-Host "Adding VM Access Extension to update password..."
    $extensionResult = Set-AzVMExtension -ResourceGroupName $ResourceGroupName `
                                         -VMName $VMName `
                                         -Name "VMAccessAgent" `
                                         -ExtensionType "VMAccessAgent" `
                                         -Publisher "Microsoft.Compute" `
                                         -TypeHandlerVersion "2.0" `
                                         -Location $vm.Location `
                                         -SettingString $publicSettings `
                                         -ProtectedSettingString $protectedSettings

    if ($extensionResult.IsSuccessStatusCode) {
        Write-Host "VM password updated successfully"
    } else {
        throw "Failed to update VM password. Status: $($extensionResult.StatusCode)"
    }
    
    # Step 5: Update the password in Key Vault
    Write-Host "Updating password in Key Vault secret..."
    $secretValue = ConvertTo-SecureString -String $newPassword -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AdminPasswordSecretName -SecretValue $secretValue -ErrorAction Stop
    Write-Host "Key Vault secret updated successfully"
    
    Write-Host "Password rotation completed successfully!"
    return $true
}
catch {
    $errorMessage = $_.Exception.Message
    Write-Error "Error during password rotation: $errorMessage"
    Write-Error $_.Exception
    throw $_.Exception
}