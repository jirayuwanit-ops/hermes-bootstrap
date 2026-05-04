# windows_remote_bootstrap_v6.ps1
# Run as Administrator — one-shot Tailscale + OpenSSH + Hermes SSH key

# 1. Admin detection + self-elevate with -NoExit
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not running as Administrator. Relaunching elevated with -NoExit..."
    $scriptPath = "$env:USERPROFILE\HermesBootstrap\hb_v6.ps1"
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

$ErrorActionPreference = "Stop"

# Start transcript log
$logPath = "$env:USERPROFILE\HermesBootstrap\bootstrap_v6.log"
Start-Transcript -Path $logPath -Append
Write-Host "Transcript logging to: $logPath"

Write-Host "=== Step 1: Check Existing Tailscale ==="

# 2. Check existing Tailscale paths
$tailscaleExe = $null
$tailscalePaths = @(
    "C:\Program Files\Tailscale\Tailscale.exe",
    "C:\Program Files\Tailscale IPN\Tailscale.exe"
)

foreach ($p in $tailscalePaths) {
    if (Test-Path $p) {
        $tailscaleExe = $p
        Write-Host "Found existing Tailscale: $p"
        break
    }
}

if (-not $tailscaleExe) {
    $tailscaleExe = (Get-Command tailscale -ErrorAction SilentlyContinue) | Select-Object -First 1 -ExpandProperty Source
}

$installed = $tailscaleExe -and (Test-Path $tailscaleExe)

if (-not $installed) {
    Write-Host "Tailscale not found. Trying winget (non-interactive)..."
    
    $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetAvailable) {
        Write-Host "Running winget install (silent, non-interactive)..."
        winget install --id Tailscale.Tailscale -e `
            --silent --disable-interactivity `
            --accept-package-agreements --accept-source-agreements `
            --verbose
        
        # Wait for install to settle
        Start-Sleep -Seconds 10
        
        # Re-check paths
        foreach ($p in $tailscalePaths) {
            if (Test-Path $p) {
                $tailscaleExe = $p
                $installed = $true
                Write-Host "Tailscale installed via winget: $p"
                break
            }
        }
        
        if (-not $installed) {
            $tailscaleCmd = Get-Command tailscale -ErrorAction SilentlyContinue
            if ($tailscaleCmd) {
                $tailscaleExe = $tailscaleCmd.Source
                $installed = $true
                Write-Host "Tailscale installed via winget (command found)"
            }
        }
    }
    
    if (-not $installed) {
        Write-Host "Winget install failed or winget not available."
        Write-Host "Opening official Tailscale download page..."
        
        Start-Process "https://tailscale.com/download/windows"
        
        Write-Host "`n=============================================="
        Write-Host "ACTION REQUIRED:"
        Write-Host "1. Install Tailscale from the page that just opened."
        Write-Host "2. Complete the installation (use defaults)."
        Write-Host "3. After install finishes, rerun this SAME command:"
        Write-Host "   New-Item -ItemType Directory -Force "$env:USERPROFILE\HermesBootstrap" | Out-Null; iwr -Uri https://raw.githubusercontent.com/jirayuwanit-ops/hermes-bootstrap/main/windows_remote_bootstrap_v6.ps1 -OutFile "$env:USERPROFILE\HermesBootstrap\hb_v6.ps1"; powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\HermesBootstrap\hb_v6.ps1""
        Write-Host "==============================================`n"
        Stop-Transcript
        exit 20
    }
} else {
    Write-Host "Tailscale already installed: $tailscaleExe"
}

# Add to PATH for current process
$env:PATH += ";" + (Split-Path $tailscaleExe)

# Verify installation
if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
    throw "Tailscale command not available after install."
}
Write-Host "Tailscale verified: $tailscaleExe"

# Start Tailscale if not running
$tailscaleIp = $null
if (-not (Get-Process tailscale -ErrorAction SilentlyContinue)) {
    Write-Host "Starting Tailscale..."
    & "$tailscaleExe" up --accept-routes=false
    Write-Host "Tailscale started."
}

# Get Tailscale IP (no blocking if already have IP)
Write-Host "`n=== Step 2: Get Tailscale IP ==="
$tailscaleIp = (tailscale ip -4) -replace ' ','' -replace "`n",''
if (-not $tailscaleIp) {
    Write-Host "No Tailscale IP yet. Please complete browser login if prompted."
    Read-Host "After Tailscale login is complete, press Enter to continue..."
    $tailscaleIp = (tailscale ip -4) -replace ' ','' -replace "`n",''
}

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
Write-Host "BOOTSTRAP_DONE=True"
Write-Host "SSH listening on Tailscale only (port 22)."
Write-Host "`nNext: Provide these details to Hermes for SSH verification."

Stop-Transcript
