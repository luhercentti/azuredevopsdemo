# Install required packages using Chocolatey
Write-Host "Starting installation of required packages..." -ForegroundColor Green

# Set error action preference to continue so one failure doesn't stop everything
$ErrorActionPreference = "Continue"

# Make sure Chocolatey is installed
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Chocolatey not found. Installing Chocolatey first..." -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Host "Chocolatey installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to install Chocolatey: $_" -ForegroundColor Red
        exit 1
    }
}

# Simple function to install packages with retry logic
function Install-Package {
    param (
        [string]$PackageName,
        [int]$MaxRetries = 2
    )
    
    Write-Host "Installing $PackageName..." -ForegroundColor Yellow
    
    $attempt = 0
    $success = $false
    
    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++
        try {
            # Add --no-progress to avoid output getting truncated in Azure Pipelines logs
            choco install $PackageName -y --no-progress --timeout=1800
            if ($LASTEXITCODE -eq 0) {
                Write-Host "$PackageName installed successfully." -ForegroundColor Green
                $success = $true
            } else {
                Write-Host "Failed to install $PackageName (Attempt $attempt of $MaxRetries). Exit code: $LASTEXITCODE" -ForegroundColor Red
                if ($attempt -lt $MaxRetries) {
                    Write-Host "Retrying in 30 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 30
                }
            }
        } catch {
            Write-Host "Error installing $PackageName (Attempt $attempt of $MaxRetries): $_" -ForegroundColor Red
            if ($attempt -lt $MaxRetries) {
                Write-Host "Retrying in 30 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 30
            }
        }
    }
    
    return $success
}

# Ensure Chocolatey is in PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

# Install Microsoft Office
$officeSuccess = Install-Package -PackageName "office365proplus"

# Install Node.js
$nodeSuccess = Install-Package -PackageName "nodejs"

# Install Java (JDK 11)
$javaSuccess = Install-Package -PackageName "openjdk11"

# Configure Java environment variables
if ($javaSuccess) {
    Write-Host "Configuring Java environment variables..." -ForegroundColor Yellow
    $javaPath = "C:\Program Files\OpenJDK\openjdk-11"
    
    # Set JAVA_HOME environment variable
    [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $javaPath, [System.EnvironmentVariableTarget]::Machine)
    
    # Add Java bin folder to PATH if it's not already there
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
    $javaBinPath = "$javaPath\bin"
    
    if ($machinePath -notlike "*$javaBinPath*") {
        $newPath = "$machinePath;$javaBinPath"
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, [System.EnvironmentVariableTarget]::Machine)
        Write-Host "Added Java bin directory to PATH." -ForegroundColor Green
    } else {
        Write-Host "Java bin directory already in PATH." -ForegroundColor Green
    }
}

# Install Visual Studio Code
$vscodeSuccess = Install-Package -PackageName "vscode"

# Install Git
$gitSuccess = Install-Package -PackageName "git"

# Print environment variables
Write-Host "Current System Environment Variables:" -ForegroundColor Cyan
Get-ChildItem Env: | Sort-Object Name | Format-Table -AutoSize

# Summary of installations
Write-Host "Installation Summary:" -ForegroundColor Cyan
Write-Host "Microsoft Office: $(if ($officeSuccess) { 'Success' } else { 'Failed' })"
Write-Host "Node.js: $(if ($nodeSuccess) { 'Success' } else { 'Failed' })"
Write-Host "Java JDK: $(if ($javaSuccess) { 'Success' } else { 'Failed' })"
Write-Host "Visual Studio Code: $(if ($vscodeSuccess) { 'Success' } else { 'Failed' })"
Write-Host "Git: $(if ($gitSuccess) { 'Success' } else { 'Failed' })"

Write-Host "Installation completed. The VM will restart in 30 seconds..." -ForegroundColor Green
Start-Sleep -Seconds 30

# Restart the VM
Restart-Computer -Force