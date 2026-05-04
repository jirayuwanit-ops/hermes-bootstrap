# windows_openssh_setup_v10.ps1
# OpenSSH-only setup — assumes Tailscale already working
# Run as Administrator

$ErrorActionPreference = "Stop"

# Self-elevate with -NoExit if not admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "Not running as Administrator. Relaunching elevated..."
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

Write-Host "=== OpenSSH-only Setup v10 ==="
Write-Host "Tailscale IP: $(& 'C:\Program Files\Tailscale\Tailscale.exe' ip -4 2>&1)"

# Step 1: Install OpenSSH via winget (preferred) or Win32-OpenSSH zip fallback
Write-Host "=== Step 1: Install OpenSSH Server ==="
$sshdInstalled = Get-Service sshd -ErrorAction SilentlyContinue

if ($sshdInstalled) {
  Write-Host "OpenSSH already installed."
} else {
  # Try winget first
  Write-Host "Trying winget install..."
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget) {
    winget install --id Microsoft.OpenSSH.Beta --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    Start-Sleep 10
  }
  
  # Check if installed, if not use Win32-OpenSSH zip
  $sshdInstalled = Get-Service sshd -ErrorAction SilentlyContinue
  if (-not $sshdInstalled) {
    Write-Host "Winget failed or not available. Using Win32-OpenSSH zip..."
    $openSshDir = "C:\Program Files\OpenSSH-Win64"
    if (-not (Test-Path $openSshDir)) {
      $zipUrl = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip"
      $zipFile = "$env:TEMP\OpenSSH-Win64.zip"
      Start-BitsTransfer -Source $zipUrl -Destination $zipFile
      Expand-Archive $zipFile -DestinationPath "C:\Program Files\" -Force
      Rename-Item "C:\Program Files\OpenSSH-Win64" $openSshDir -ErrorAction SilentlyContinue
    }
    
    # Install sshd
    & "$openSshDir\install-sshd.ps1"
    $sshdInstalled = Get-Service sshd -ErrorAction SilentlyContinue
  }
}

if (-not $sshdInstalled) {
  Write-Host "ERROR: OpenSSH installation failed."
  exit 1
}

# Step 2: Configure sshd
Write-Host "=== Step 2: Configure sshd ==="
$sshdConfig = "C:\ProgramData\ssh\sshd_config"
if (-not (Test-Path $sshdConfig)) {
  # Try alternate path
  $sshdConfig = "C:\Program Files\OpenSSH-Win64\sshd_config"
}

# Ensure key auth enabled
$configContent = Get-Content $sshdConfig -Raw -ErrorAction SilentlyContinue
if ($configContent -notmatch "PubkeyAuthentication yes") {
  Add-Content $sshdConfig "`nPubkeyAuthentication yes"
}
if ($configContent -notmatch "PasswordAuthentication no") {
  Add-Content $sshdConfig "`nPasswordAuthentication no"
}

# Step 3: Add Hermes public key
Write-Host "=== Step 3: Add Hermes SSH public key ==="
$userProfile = $env:USERPROFILE
$sshDir = "$userProfile\.ssh"
$authKeys = "$sshDir\authorized_keys"

New-Item -ItemType Directory -Force $sshDir | Out-Null

$hermesPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICnjQFSqL7S8kTHphU2Mcrl8di+0ZX8AYHG5YbIf1M0b hermes@ec2-to-windows"

if (Test-Path $authKeys) {
  $existingKeys = Get-Content $authKeys
  if ($existingKeys -notcontains $hermesPubKey) {
    Add-Content $authKeys $hermesPubKey
  }
} else {
  Set-Content $authKeys $hermesPubKey
}

# Restrict permissions (Windows SSH requires this)
icacls $sshDir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null
icacls $authKeys /inheritance:r /grant:r "$($env:USERNAME):(F)" | Out-Null

# Step 4: Firewall — allow TCP 22 only from Tailscale range
Write-Host "=== Step 4: Configure firewall ==="
Remove-NetFirewallRule -DisplayName "OpenSSH Tailscale Only" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "OpenSSH Tailscale Only" -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress 100.64.0.0/10 -Action Allow | Out-Null

# Step 5: Start sshd
Write-Host "=== Step 5: Start sshd service ==="
Set-Service sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue

Start-Sleep 3

# Step 6: Verify
Write-Host "=== Step 6: Verification ==="
$sshdRunning = Get-Service sshd | Where-Object {$_.Status -eq "Running"}
if (-not $sshdRunning) {
  Write-Host "ERROR: sshd not running."
  exit 1
}

# Test local port 22
$portTest = Test-NetConnection -ComputerName localhost -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue
if (-not $portTest) {
  Write-Host "ERROR: Port 22 not listening."
  exit 1
}

Write-Host "========================================="
Write-Host "OPENSSH_DONE=True"
Write-Host "Username: $env:USERNAME"
Write-Host "Tailscale IP: $(& 'C:\Program Files\Tailscale\Tailscale.exe' ip -4 2>&1)"
Write-Host "sshd: Running"
Write-Host "Firewall: TCP 22 allowed from 100.64.0.0/10 only"
Write-Host "========================================="
