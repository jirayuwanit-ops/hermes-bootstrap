# windows_remote_bootstrap_v9.ps1
# Run as Administrator — Tailscale (NoState fix v2) + OpenSSH + Hermes SSH key
$ErrorActionPreference = "Stop"

Write-Host "=== Step 1: Check Tailscale ==="
$tailscaleExe = @(
  "C:\Program Files\Tailscale\Tailscale.exe",
  "C:\Program Files\Tailscale IPN\Tailscale.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $tailscaleExe) {
  Write-Host "Tailscale not found. Installing..."
  winget install --id Tailscale.Tailscale -e --silent --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
  Start-Sleep 10
  $tailscaleExe = @(
    "C:\Program Files\Tailscale\Tailscale.exe",
    "C:\Program Files\Tailscale IPN\Tailscale.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $tailscaleExe) {
    Write-Host "Opening Tailscale download page..."
    Start-Process "https://tailscale.com/download/windows"
    Write-Host "Install Tailscale manually, then rerun this script."
    exit 20
  }
}

Write-Host "Tailscale found at: $tailscaleExe"

# Detect and start Windows Tailscale service
Write-Host "=== Starting Tailscale service ==="
$tailscaleServices = Get-Service *tailscale* -ErrorAction SilentlyContinue
if ($tailscaleServices) {
  $tailscaleServices | Format-Table Name,Status,StartType
  foreach ($svc in $tailscaleServices) {
    if ($svc.Status -ne 'Running') {
      Write-Host "Starting service: $($svc.Name)..."
      Start-Service $svc.Name -ErrorAction SilentlyContinue
    }
  }
} else {
  Write-Host "No Tailscale services found. Trying to start manually..."
}

# Start GUI/IPN app explicitly
Write-Host "Starting Tailscale GUI..."
$ipnExe = "C:\Program Files\Tailscale\tailscale-ipn.exe"
if (Test-Path $ipnExe) {
  Start-Process $ipnExe -ErrorAction SilentlyContinue
  Write-Host "Started tailscale-ipn.exe"
}
Start-Process $tailscaleExe -ArgumentList "up" -ErrorAction SilentlyContinue
Start-Sleep 5

# Check service status again
Write-Host "=== Tailscale Service Status ==="
Get-Service *tailscale* | Format-Table Name,Status,StartType

# Try auth-key mode if environment variable exists
if ($env:HERMES_TAILSCALE_AUTHKEY) {
  Write-Host "Auth-key detected, using --auth-key mode..."
  & $tailscaleExe up --auth-key $env:HERMES_TAILSCALE_AUTHKEY --hostname benz-windows --accept-routes=false 2>&1 | Out-Null
} else {
  Write-Host "Running tailscale up..."
  & $tailscaleExe up --accept-routes=false 2>&1 | Out-Null
}
Start-Sleep 3

# Poll for IP for up to 120 seconds
Write-Host "Polling for Tailscale IP (up to 120 seconds)..."
$tailscaleIp = ""
$maxWait = 120
$elapsed = 0
$pollInterval = 5

while ($elapsed -lt $maxWait) {
  try {
    $ipOutput = & $tailscaleExe ip -4 2>&1 | Out-String
    if ($ipOutput -match '100\.\d+\.\d+\.\d+') {
      $tailscaleIp = $Matches[0]
      Write-Host "Tailscale IP acquired: $tailscaleIp"
      break
    } elseif ($ipOutput -match "NoState|starting") {
      Write-Host "Tailscale status: NoState/starting... waiting ($elapsed/$maxWait seconds)"
    }
  } catch {}

  Start-Sleep $pollInterval
  $elapsed += $pollInterval
}

if (-not $tailscaleIp) {
  Write-Host "Failed to acquire Tailscale IP after $maxWait seconds."
  Write-Host "Opening Tailscale tray app/login page..."
  Start-Process "tailscale.exe"
  Start-Sleep 2
  Write-Host "Open the Tailscale tray app (system tray), sign in, then rerun v9."
  exit 20
}

# Print Tailscale status
Write-Host "=== Tailscale Status ==="
& $tailscaleExe status
Write-Host "Windows Tailscale IP: $tailscaleIp"

Write-Host "=== Step 2: Install OpenSSH Server (winget or Win32-OpenSSH) ==="
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshd) {
  Write-Host "OpenSSH Server already installed."
} else {
  # Try winget first
  Write-Host "Trying winget install Microsoft.OpenSSH.Beta..."
  winget search openssh 2>&1 | Out-Null
  winget install --id Microsoft.OpenSSH.Beta -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
  Start-Sleep 15
  $sshd = Get-Service sshd -ErrorAction SilentlyContinue
  if (-not $sshd) {
    Write-Host "winget install failed, trying Win32-OpenSSH GitHub release..."
    $zipUrl = "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip"
    $zipPath = "$env:ProgramData\HermesBootstrap\OpenSSH-Win64.zip"
    New-Item -ItemType Directory -Force "$env:ProgramData\HermesBootstrap" | Out-Null
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    $extractPath = "C:\Program Files\OpenSSH-Win64"
    Expand-Archive -Path $zipPath -DestinationPath "C:\Program Files" -Force
    cd $extractPath
    .\install-sshd.ps1
    cd ~
  }
}

Write-Host "=== Step 3: Configure sshd ==="
$sshdConfig = "C:\ProgramData\ssh\sshd_config"
if (Test-Path $sshdConfig) {
  (Get-Content $sshdConfig) -replace '^#?PubkeyAuthentication.*', 'PubkeyAuthentication yes' |
    Set-Content $sshdConfig
  (Get-Content $sshdConfig) -replace '^#?PasswordAuthentication.*', 'PasswordAuthentication no' |
    Set-Content $sshdConfig
} else {
  Write-Host "sshd_config not found, creating minimal config..."
  @"
Port 22
PubkeyAuthentication yes
PasswordAuthentication no
Subsystem sftp sftp-server.exe
"@ | Out-File -Encoding ASCII $sshdConfig
}

Write-Host "=== Step 4: Add Hermes EC2 public key ==="
$sshDir = "$env:USERPROFILE\.ssh"
New-Item -ItemType Directory -Force $sshDir | Out-Null
$authorizedKeys = "$sshDir\authorized_keys"
$hermesPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICnjQFSqL7S8kTHphU2Mcrl8di+0ZX8AYHG5YbIf1M0b hermes@ec2-to-windows"
if (-not (Test-Path $authorizedKeys) -or -not (Select-String -Path $authorizedKeys -Pattern "hermes@ec2-to-windows" -Quiet)) {
  Add-Content -Path $authorizedKeys -Value $hermesPubKey
}
icacls $sshDir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" /T
icacls $authorizedKeys /inheritance:r /grant:r "$($env:USERNAME):(R)"

Write-Host "=== Step 5: Firewall rule (restrict to Tailscale) ==="
Remove-NetFirewallRule -DisplayName "OpenSSH Tailscale Only" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "OpenSSH Tailscale Only" -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress "100.64.0.0/10" -Action Allow

Write-Host "=== Step 6: Start sshd ==="
Set-Service sshd -StartupType Automatic
Start-Service sshd
Start-Sleep 5
Get-Service sshd

Write-Host "=== Step 7: Verify locally ==="
Test-NetConnection 127.0.0.1 -Port 22 | Format-List RemoteAddress,RemotePort,TcpTestSucceeded

Write-Host "=== DONE ==="
Write-Host "Windows Tailscale IP: $tailscaleIp"
Write-Host "Windows username: $env:USERNAME"
Write-Host "OPENSSH_DONE=True"
