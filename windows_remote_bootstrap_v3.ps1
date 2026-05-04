# windows_remote_bootstrap_v3.ps1
# Run as Administrator — one-shot Tailscale + OpenSSH + Hermes SSH key
$ErrorActionPreference = "Stop"

Write-Host "=== Step 1: Install Tailscale ==="

# Pre-clean HermesBootstrap installer files only
$installerDir = "C:\ProgramData\HermesBootstrap"
if (-not (Test-Path $installerDir)) {
    New-Item -ItemType Directory -Path $installerDir -Force | Out-Null
}
Remove-Item "$installerDir\Tailscale-installer.*" -Force -ErrorAction SilentlyContinue

$tailscaleExe = $null

if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
    Write-Host "Downloading Tailscale installer..."
    
    # Try MSI first
    $msiUrl = "https://tailscale.com/download/windows/tailscale-setup-latest.msi"
    $msiPath = Join-Path $installerDir "tailscale-setup-latest.msi"
    
    # Try Start-BitsTransfer first (more reliable)
    $bitsAvailable = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue
    $downloaded = $false
    
    if ($bitsAvailable) {
        Write-Host "Using Start-BitsTransfer for MSI..."
        try {
            Start-BitsTransfer -Source $msiUrl -Destination $msiPath -ErrorAction Stop
            $downloaded = $true
        } catch {
            Write-Host "Start-BitsTransfer failed, trying EXE with fallback..."
        }
    }
    
    if (-not $downloaded) {
        # Fallback to EXE
        $exeUrl = "https://tailscale.com/download/windows/tailscale-setup-latest.exe"
        $exePath = Join-Path $installerDir "tailscale-installer.exe"
        
        if ($bitsAvailable) {
            try {
                Start-BitsTransfer -Source $exeUrl -Destination $exePath -ErrorAction Stop
                $msiPath = $exePath
                $downloaded = $true
            } catch {
                Write-Host "BitsTransfer failed, using Invoke-WebRequest..."
            }
        }
        
        if (-not $downloaded) {
            Invoke-WebRequest -Uri $exeUrl -OutFile $exePath -UseBasicParsing
            $msiPath = $exePath
            $downloaded = $true
        }
    }
    
    # Verify download
    if (-not (Test-Path $msiPath)) {
        throw "Download failed: file not found at $msiPath"
    }
    $fileSize = (Get-Item $msiPath).Length
    Write-Host "Downloaded: $([math]::Round($fileSize/1MB,2)) MB"
    
    if ($fileSize -lt 50MB) {
        Remove-Item $msiPath -Force
        throw "Downloaded file too small: $fileSize bytes. Corrupted installer."
    }
    
    # Install based on file type
    if ($msiPath -match '\.msi$') {
        Write-Host "Installing via msiexec..."
        Start-Process "msiexec.exe" -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait
    } else {
        Write-Host "Installing EXE..."
        Start-Process -FilePath $msiPath -ArgumentList "/quiet" -Wait
    }
    
    Write-Host "Tailscale installed."
} else {
    Write-Host "Tailscale already installed."
}

# Find tailscale.exe
$tailscalePaths = @(
    "C:\Program Files\Tailscale\Tailscale.exe",
    "C:\Program Files\Tailscale IPN\Tailscale.exe"
)
foreach ($p in $tailscalePaths) {
    if (Test-Path $p) {
        $tailscaleExe = $p
        break
    }
}
if (-not $tailscaleExe) {
    throw "Tailscale.exe not found after install."
}

# Add to PATH for current process
$env:PATH += ";$(Split-Path $tailscaleExe)"

# Verify installation
if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
    throw "Tailscale command not available after install."
}
Write-Host "Tailscale verified: $tailscaleExe"

# Start Tailscale if not running
if (-not (Get-Process tailscale -ErrorAction SilentlyContinue)) {
    Write-Host "Starting Tailscale..."
    & "$tailscaleExe" up
    Write-Host "Tailscale started. Please complete browser login if prompted."
    Read-Host "After Tailscale login is complete, press Enter to continue..."
}

Write-Host "`n=== Step 2: Get Tailscale IP ==="
$tailscaleIp = (tailscale ip -4) -replace ' ','' -replace "`n",''
if (-not $tailscaleIp) {
    throw "Could not get Tailscale IP. Is Tailscale logged in?"
}
Write-Host "Windows Tailscale IP: $tailscaleIp"

Write-Host "`n=== Step 3: Install OpenSSH Server ==="
if (-not (Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*" | Where-Object State -eq "Installed")) {
    Write-Host "Installing OpenSSH Server..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
Write-Host "OpenSSH Server installed and running."

Write-Host "`n=== Step 4: Configure sshd_config ==="
$sshdConfig = "C:\ProgramData\ssh\sshd_config"
$config = Get-Content $sshdConfig
if ($config -notmatch "^\s*PubkeyAuthentication\s+yes") {
    Add-Content $sshdConfig "`nPubkeyAuthentication yes"
}
if ($config -notmatch "^\s*PasswordAuthentication\s+no") {
    Add-Content $sshdConfig "`nPasswordAuthentication no"
}
Restart-Service sshd
Write-Host "SSH configured: Pubkey auth enabled, Password auth disabled."

Write-Host "`n=== Step 5: Firewall rule (Tailscale only) ==="
if (-not (Get-NetFirewallRule -DisplayName "SSH Tailscale" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "SSH Tailscale" `
        -Direction Inbound -Protocol TCP -LocalPort 22 `
        -RemoteAddress 100.64.0.0/10 -Action Allow
    Write-Host "Firewall rule added: SSH allowed only from Tailscale network."
} else {
    Write-Host "Firewall rule already exists."
}

Write-Host "`n=== Step 6: Prepare .ssh and authorized_keys ==="
$userProfile = $env:USERPROFILE
$sshDir = Join-Path $userProfile ".ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    Write-Host "Created .ssh directory: $sshDir"
}

$authorizedKeys = Join-Path $sshDir "authorized_keys"
$hermesPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICnjQFSqL7S8kTHphU2Mcrl8di+0ZX8AYHG5YbIf1M0b hermes@ec2-to-windows"

if (Test-Path $authorizedKeys) {
    $existing = Get-Content $authorizedKeys
    if ($existing -notcontains $hermesPubKey) {
        Add-Content $authorizedKeys "`n$hermesPubKey"
        Write-Host "Hermes public key appended to authorized_keys."
    } else {
        Write-Host "Hermes public key already present in authorized_keys."
    }
} else {
    Set-Content $authorizedKeys $hermesPubKey
    Write-Host "authorized_keys created with Hermes public key."
}

# Set strict permissions: only current user full control
icacls "$sshDir" /inheritance:r /grant:r "$($env:USERNAME):(F)" /T | Out-Null
icacls $authorizedKeys /inheritance:r /grant:r "$($env:USERNAME):(R)" | Out-Null
Write-Host "Permissions set: only $($env:USERNAME) can access .ssh and authorized_keys."

Write-Host "`n=== Bootstrap Complete ==="
Write-Host "Windows Tailscale IP: $tailscaleIp"
Write-Host "Windows username: $($env:USERNAME)"
Write-Host "SSH listening on Tailscale only (port 22)."
Write-Host "`nNext: Provide these details to Hermes for SSH verification."
