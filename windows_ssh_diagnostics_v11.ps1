# windows_ssh_diagnostics_v11.ps1
# One-shot SSH diagnostics + temporary fix for Tailscale SSH access
# Run as Administrator

$ErrorActionPreference = "Continue"

# Self-elevate with -NoExit if not admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "Not running as Administrator. Relaunching elevated..."
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

Write-Host "========================================="
Write-Host "SSH Diagnostics + Fix v11"
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

# Step 2: Check sshd service
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
$netstat = netstat -an | Select-String ":22"
if ($netstat) {
  $netstat | ForEach-Object { Write-Host $_ }
} else {
  Write-Host "No process listening on port 22"
}

# Step 4: Test local connection
Write-Host "=== Local Port Test ==="
try {
  $testConn = Test-NetConnection -ComputerName 127.0.0.1 -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
  Write-Host "Localhost:22 accessible: $testConn"
} catch {
  Write-Host "Local test failed: $_"
}

# Step 5: Print current firewall rules for port 22
Write-Host "=== Current Firewall Rules (Port 22) ==="
$fwRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq 22 -or $_.DisplayName -like "*SSH*" -or $_.DisplayName -like "*22*' }
if ($fwRules) {
  $fwRules | ForEach-Object {
    $rule = $_
    Write-Host "Rule: $($rule.DisplayName)"
    Write-Host "  Enabled: $($rule.Enabled)"
    Write-Host "  Direction: $($rule.Direction)"
    Write-Host "  Action: $($rule.Action)"
    $addrFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
    if ($addrFilter) {
      Write-Host "  RemoteAddress: $($addrFilter.RemoteAddress)"
    }
    Write-Host ""
  }
} else {
  Write-Host "No firewall rules found for port 22"
}

# Step 6: Disable clearly blocking OpenSSH rules (only if blocking)
Write-Host "=== Disabling Blocking Rules ==="
$blockingRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { 
  ($_.DisplayName -like "*SSH*" -or $_.DisplayName -like "*22*" -or $_.DisplayName -like "*OpenSSH*") -and 
  $_.Action -eq "Block" 
}
if ($blockingRules) {
  $blockingRules | ForEach-Object {
    Write-Host "Disabling blocking rule: $($_.DisplayName)"
    Set-NetFirewallRule -DisplayName $_.DisplayName -Enabled False
  }
} else {
  Write-Host "No blocking rules found"
}

# Step 7: Add temporary test firewall rule for Tailscale
Write-Host "=== Adding Temporary Test Rule ==="
Remove-NetFirewallRule -DisplayName "OpenSSH Temp Allow Tailscale Test" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "OpenSSH Temp Allow Tailscale Test" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 22 `
  -RemoteAddress 100.64.0.0/10 `
  -Action Allow | Out-Null
Write-Host "Added rule: OpenSSH Temp Allow Tailscale Test (Tailscale range only)"

# Verify the rule
$tempRule = Get-NetFirewallRule -DisplayName "OpenSSH Temp Allow Tailscale Test" -ErrorAction SilentlyContinue
if ($tempRule) {
  Write-Host "Temp rule verified: Enabled=$($tempRule.Enabled), Action=$($tempRule.Action)"
}

# Final verification
Write-Host "=== Final Verification ==="
$sshdFinal = Get-Service sshd -ErrorAction SilentlyContinue
Write-Host "sshd status: $(if($sshdFinal){$sshdFinal.Status}else{'NOT FOUND'})"

$listenFinal = netstat -an | Select-String ":22"
Write-Host "Port 22 listening: $(if($listenFinal){'YES'}else{'NO'})"

Write-Host "========================================="
Write-Host "SSH_DIAG_READY=True"
Write-Host "Windows Tailscale IP: $(& $tailscaleExe ip -4 2>&1)"
Write-Host "Windows username: $username"
Write-Host "========================================="
Write-Host "Now EC2 can test SSH connection"
