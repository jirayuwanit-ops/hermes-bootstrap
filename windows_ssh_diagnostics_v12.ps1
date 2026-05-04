# windows_ssh_diagnostics_v12.ps1
# Simplified SSH diagnostics + temp Tailscale firewall rule
# Run as Administrator

$ErrorActionPreference = "Stop"

# Self-elevate with -NoExit if not admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "Not running as Administrator. Relaunching elevated..."
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

Write-Host "========================================="
Write-Host "SSH Diagnostics v12"
Write-Host "========================================="

# Step 1: Print basic info
Write-Host "=== Basic Info ==="
$username = $env:USERNAME
Write-Host "Windows username: $username"

$tailscaleExe = "C:\Program Files\Tailscale\Tailscale.exe"
if (Test-Path $tailscaleExe) {
  $tsIp = & $tailscaleExe ip -4 2>&1 | Out-String
  Write-Host "Tailscale IP: $tsIp"
} else {
  Write-Host "Tailscale not found at: $tailscaleExe"
}

# Step 2: Ensure sshd running
Write-Host "=== SSHD Service ==="
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshd) {
  Write-Host "Name: $($sshd.Name)"
  Write-Host "Status: $($sshd.Status)"
  Write-Host "StartType: $($sshd.StartType)"
  
  if ($sshd.Status -ne "Running") {
    Write-Host "Starting sshd..."
    Set-Service sshd -StartupType Automatic
    Start-Service sshd -ErrorAction SilentlyContinue
    Start-Sleep 3
    $sshd = Get-Service sshd
    Write-Host "Status after start: $($sshd.Status)"
  }
} else {
  Write-Host "ERROR: sshd service not found!"
}

# Step 3: Check port 22 listening
Write-Host "=== Port 22 Listening ==="
netstat -an | findstr ":22"
if (-not $?) {
  Write-Host "No process listening on port 22"
}

# Step 4: Add temp firewall rule (Tailscale only, no disable)
Write-Host "=== Adding Temp Firewall Rule ==="
Remove-NetFirewallRule -DisplayName "OpenSSH Temp Allow Tailscale Test" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "OpenSSH Temp Allow Tailscale Test" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 22 `
  -RemoteAddress 100.64.0.0/10 `
  -Action Allow | Out-Null
Write-Host "Added rule: OpenSSH Temp Allow Tailscale Test (Tailscale range only)"

# Final output
Write-Host "========================================="
Write-Host "SSH_DIAG_READY=True"
Write-Host "Windows Tailscale IP: $tsIp"
Write-Host "Windows username: $username"
Write-Host "========================================="
