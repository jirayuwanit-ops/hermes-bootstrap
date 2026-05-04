# windows_remote_access_repair_v15.ps1
# State-machine: Tailscale → sshd → firewall → READY
# Run as Administrator

$ErrorActionPreference = "Continue"

# Self-elevate with -NoExit if not admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "Not running as Administrator. Relaunching elevated..."
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

# Transcript log to user profile
$logDir = "$env:USERPROFILE\HermesBootstrap\Logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$logFile = "$logDir\remote_repair_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $logFile -Append

Write-Host "========================================="
Write-Host "Remote Access Repair v15"
Write-Host "========================================="

$username = $env:USERNAME
Write-Host "Windows username: $username"

$tailscaleExe = "C:\Program Files\Tailscale\Tailscale.exe"
$tailscaleIp = $null

# ==========================================
# PHASE 1: Tailscale online
# ==========================================
Write-Host "=== PHASE 1: Tailscale Online ==="

if (-not (Test-Path $tailscaleExe)) {
  Write-Host "ERROR: Tailscale not found at $tailscaleExe"
  Write-Host "Please install Tailscale first: https://tailscale.com/download/windows"
  Stop-Transcript
  exit 1
}

# Restart Tailscale service
Write-Host "Restarting Tailscale service..."
Stop-Service Tailscale -Force -ErrorAction SilentlyContinue
Start-Sleep 2
Start-Service Tailscale -ErrorAction SilentlyContinue
Start-Sleep 3

# Start GUI
$ipnExe = "C:\Program Files\Tailscale\tailscale-ipn.exe"
if (Test-Path $ipnExe) {
  Get-Process tailscale-ipn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Process $ipnExe
  Write-Host "Started tailscale-ipn.exe"
}

# Run tailscale up (avoid logout unless needed)
Write-Host "Running tailscale up..."
$upOutput = & $tailscaleExe up --accept-routes=false --hostname desktop-prlacvl 2>&1 | Out-String
Write-Host $upOutput

# Check for login URL
$loginUrl = ""
if ($upOutput -match 'https://login\.tailscale\.com/[^\s]+') {
  $loginUrl = $Matches[0]
  Write-Host "========================================="
  Write-Host "LOGIN REQUIRED:"
  Write-Host $loginUrl
  Write-Host "========================================="
}

# Poll for Tailscale IP (up to 180 seconds)
Write-Host "Polling for Tailscale IP (max 180s)..."
$maxWait = 180
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
  Write-Host "========================================="
  Write-Host "TAILSCALE_NEEDS_LOGIN=True"
  if ($loginUrl) {
    Write-Host "Login URL: $loginUrl"
  }
  Write-Host "========================================="
  Stop-Transcript
  exit 20
}

Write-Host "TAILSCALE_READY=True"
Write-Host "Windows Tailscale IP: $tailscaleIp"

# ==========================================
# PHASE 2: sshd running/listening
# ==========================================
Write-Host "=== PHASE 2: sshd Service ==="

$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if (-not $sshd) {
  Write-Host "ERROR: sshd service not found!"
  Stop-Transcript
  exit 1
}

Set-Service sshd -StartupType Automatic
Restart-Service sshd -Force
Start-Sleep 5

$sshdStatus = (Get-Service sshd).Status
Write-Host "sshd status: $sshdStatus"

Write-Host "Checking port 22..."
$port22 = netstat -an | Select-String ":22"
if ($port22) {
  Write-Host "Port 22 listening:"
  Write-Host $port22
} else {
  Write-Host "WARNING: Port 22 not listening"
}

# ==========================================
# PHASE 3: Firewall (script-owned rules only)
# ==========================================
Write-Host "=== PHASE 3: Firewall Rules ==="

# Remove ONLY script-owned rules
$scriptRules = @(
  "OpenSSH Temp Allow Tailscale Test",
  "OpenSSH Tailscale Only",
  "OpenSSH Tailscale Range",
  "OpenSSH Allow All Interfaces",
  "ICMPv4 Allow Inbound",
  "OpenSSH Interface Fix"
)

foreach ($ruleName in $scriptRules) {
  $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Host "Removing: $ruleName"
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
  }
}

# Add Tailscale-only rules
Write-Host "Adding Tailscale-range rules..."

New-NetFirewallRule -DisplayName "OpenSSH Tailscale Range" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 22 `
  -RemoteAddress 100.64.0.0/10 `
  -Action Allow | Out-Null
Write-Host "Created: OpenSSH Tailscale Range"

New-NetFirewallRule -DisplayName "ICMPv4 Tailscale Only" `
  -Direction Inbound `
  -Protocol ICMPv4 `
  -RemoteAddress 100.64.0.0/10 `
  -Action Allow | Out-Null
Write-Host "Created: ICMPv4 Tailscale Only"

# ==========================================
# FINAL: Print READY
# ==========================================
Write-Host "========================================="
Write-Host "REMOTE_ACCESS_READY=True"
Write-Host "Windows Tailscale IP: $tailscaleIp"
Write-Host "Windows username: $username"
Write-Host "sshd: $sshdStatus"
Write-Host "port22: $(if($port22){'Listening'}else{'WARNING'})"
Write-Host "Firewall: Tailscale range only (100.64.0.0/10)"
Write-Host "Log: $logFile"
Write-Host "========================================="

Stop-Transcript
