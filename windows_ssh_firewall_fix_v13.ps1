# windows_ssh_firewall_fix_v13.ps1
# Aggressive firewall fix - remove all port 22 rules and create Tailscale-only rule
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
Write-Host "SSH Firewall Fix v13"
Write-Host "========================================="

# Step 1: Print info
$tailscaleExe = "C:\Program Files\Tailscale\Tailscale.exe"
if (Test-Path $tailscaleExe) {
  $tsIp = & $tailscaleExe ip -4 2>&1
  Write-Host "Tailscale IP: $tsIp"
}
Write-Host "Username: $env:USERNAME"

# Step 2: Ensure sshd running
Write-Host "=== Ensuring sshd running ==="
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshd) {
  if ($sshd.Status -ne "Running") {
    Write-Host "Starting sshd..."
    Set-Service sshd -StartupType Automatic
    Start-Service sshd
    Start-Sleep 3
  }
  Write-Host "sshd status: $((Get-Service sshd).Status)"
} else {
  Write-Host "ERROR: sshd not found"
  exit 1
}

# Step 3: Check port 22 listening
Write-Host "=== Checking port 22 ==="
$netstat = netstat -an | findstr ":22"
if ($netstat) {
  Write-Host "Port 22 listening:"
  Write-Host $netstat
} else {
  Write-Host "WARNING: Nothing listening on port 22"
}

# Step 4: Remove ALL existing firewall rules for port 22 or SSH
Write-Host "=== Removing ALL existing port 22 / SSH rules ==="
$allRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
  $rule = $_
  $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
  $rule.DisplayName -like "*SSH*" -or $rule.DisplayName -like "*22*" -or ($portFilter -and $portFilter.LocalPort -eq 22)
}

if ($allRules) {
  $allRules | ForEach-Object {
    Write-Host "Removing rule: $($_.DisplayName)"
    Remove-NetFirewallRule -DisplayName $_.DisplayName -ErrorAction SilentlyContinue
  }
} else {
  Write-Host "No existing rules found"
}

# Step 5: Create new Tailscale-only allow rule
Write-Host "=== Creating new Tailscale-only rule ==="
New-NetFirewallRule -DisplayName "OpenSSH Allow Tailscale Only" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 22 `
  -RemoteAddress 100.64.0.0/10 `
  -Action Allow | Out-Null

Write-Host "Created rule: OpenSSH Allow Tailscale Only"
Write-Host "RemoteAddress: 100.64.0.0/10"

# Step 6: Verify rule
Write-Host "=== Verifying new rule ==="
$newRule = Get-NetFirewallRule -DisplayName "OpenSSH Allow Tailscale Only" -ErrorAction SilentlyContinue
if ($newRule) {
  Write-Host "Rule exists: Yes"
  Write-Host "Enabled: $($newRule.Enabled)"
  Write-Host "Action: $($newRule.Action)"
  Write-Host "Direction: $($newRule.Direction)"
} else {
  Write-Host "ERROR: Rule not created!"
}

# Step 7: Final check
Write-Host "=== Final Check ==="
$listenCheck = netstat -an | findstr ":22"
Write-Host "Port 22 listening: $(if($listenCheck){'YES'}else{'NO'})"
$sshdCheck = (Get-Service sshd).Status
Write-Host "sshd status: $sshdCheck"

Write-Host "========================================="
Write-Host "SSH_FIREWALL_FIXED=True"
Write-Host "Tailscale IP: $tsIp"
Write-Host "Username: $env:USERNAME"
Write-Host "========================================="
