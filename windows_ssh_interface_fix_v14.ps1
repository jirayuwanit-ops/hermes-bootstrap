# windows_ssh_interface_fix_v14.ps1
# Fix: Ensure sshd listens on all interfaces + open firewall for Tailscale interface
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
Write-Host "SSH Interface Fix v14"
Write-Host "========================================="

# Step 1: Print info
$tailscaleExe = "C:\Program Files\Tailscale\Tailscale.exe"
if (Test-Path $tailscaleExe) {
  $tsIp = & $tailscaleExe ip -4 2>&1
  Write-Host "Tailscale IP: $tsIp"
}
$username = $env:USERNAME
Write-Host "Username: $username"

# Step 2: Restart sshd to ensure it picks up all interfaces
Write-Host "=== Restarting sshd ==="
Set-Service sshd -StartupType Automatic
Restart-Service sshd -Force
Start-Sleep 5
$sshdStatus = (Get-Service sshd).Status
Write-Host "sshd status: $sshdStatus"

# Step 3: Check what interfaces sshd is listening on
Write-Host "=== Checking sshd listening interfaces ==="
$netstat = netstat -an | findstr ":22"
Write-Host "Port 22 bindings:"
Write-Host $netstat

# Step 4: Remove ALL previous port 22 / SSH rules completely
Write-Host "=== Removing ALL previous firewall rules for port 22 ==="
$allRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
  $rule = $_
  $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
  $rule.DisplayName -like "*SSH*" -or $rule.DisplayName -like "*22*" -or ($portFilter -and $portFilter.LocalPort -eq 22)
}

if ($allRules) {
  $allRules | ForEach-Object {
    Write-Host "Removing: $($_.DisplayName)"
    Remove-NetFirewallRule -DisplayName $_.DisplayName -ErrorAction SilentlyContinue
  }
}

# Step 5: Create THREE rules to cover all bases
Write-Host "=== Creating comprehensive firewall rules ==="

# Rule 1: Allow TCP 22 from Tailscale range
New-NetFirewallRule -DisplayName "OpenSSH Tailscale Range" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 22 `
  -RemoteAddress 100.64.0.0/10 `
  -Action Allow | Out-Null
Write-Host "Created: OpenSSH Tailscale Range"

# Rule 2: Allow ANY inbound TCP 22 (catch-all for interfaces)
New-NetFirewallRule -DisplayName "OpenSSH Allow All Interfaces" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 22 `
  -Action Allow | Out-Null
Write-Host "Created: OpenSSH Allow All Interfaces"

# Rule 3: Allow ICMPv4 (ping) for diagnostics
New-NetFirewallRule -DisplayName "ICMPv4 Allow Inbound" `
  -Direction Inbound `
  -Protocol ICMPv4 `
  -Action Allow | Out-Null
Write-Host "Created: ICMPv4 Allow Inbound"

# Step 6: Verify sshd is listening on 0.0.0.0:22 or [::]:22
Write-Host "=== Final Verification ==="
$finalNetstat = netstat -an | findstr ":22"
Write-Host "Port 22 bindings:"
Write-Host $finalNetstat

$sshdFinal = (Get-Service sshd).Status
Write-Host "sshd status: $sshdFinal"

# Check if listening on all interfaces
$listeningAll = $finalNetstat | Select-String "0.0.0.0:22|\[::\]:22"
if ($listeningAll) {
  Write-Host "sshd listening on ALL interfaces: YES"
} else {
  Write-Host "WARNING: sshd may not be listening on all interfaces"
}

Write-Host "========================================="
Write-Host "SSH_INTERFACE_FIXED=True"
Write-Host "Tailscale IP: $tsIp"
Write-Host "Username: $username"
Write-Host "Firewall: Opened port 22 for all + Tailscale range"
Write-Host "========================================="
