# Bootstrap.ps1 - Enhanced Version
$ErrorActionPreference = "Stop"

# 1. Create log directory
$logPath = "C:\bootstrap-logs"
if (!(Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath }

Start-Transcript -Path "$logPath\bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# 2. Install Chocolatey
try {
    if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Output "Installing Chocolatey..."
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + 
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Write-Output "Chocolatey installed successfully"
        "SUCCESS: Chocolatey installed $(Get-Date)" | Out-File "$logPath\chocolatey-install.log"
    }
    else {
        Write-Output "Chocolatey already installed"
    }
}
catch {
    $_ | Out-File "$logPath\error.log"
    throw "Failed to install Chocolatey: $_"
}

# 3. Basic validation
try {
    choco --version | Out-File "$logPath\choco-version.log"
    Write-Output "Chocolatey version: $(choco --version)"
}
catch {
    $_ | Out-File "$logPath\validation-error.log"
    throw "Chocolatey validation failed: $_"
}

Stop-Transcript