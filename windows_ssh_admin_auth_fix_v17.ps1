# windows_ssh_admin_auth_fix_v17.ps1
# Fix SSH for Windows Admin users (administrators_authorized_keys)
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
Write-Host "SSH Admin Auth Fix v17"
Write-Host "========================================="

$username = $env:USERNAME
Write-Host "Username: $username"

# Step1: Check if user is admin
$isAdminUser = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "Is Admin user: $isAdminUser"

# Step2: Setup both authorized_keys and administrators_authorized_keys
Write-Host "=== Step2: Setup SSH authorized keys ==="
$sshDir = "$env:USERPROFILE\.ssh"
$authKeys = "$sshDir\authorized_keys"
$adminAuthKeys = "$sshDir\administrators_authorized_keys"

# Ensure .ssh directory exists
New-Item -ItemType Directory -Force $sshDir | Out-Null

# Hermes public key
$hermesPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICnjQFSqL7S8kTHphU2Mcrl8di+0ZX8AYHG5YbIf1M0b hermes@ec2-to-windows"

# Write to authorized_keys (regular)
Write-Host "Writing to authorized_keys..."
Set-Content $authKeys $hermesPubKey -NoNewline
Add-Content $authKeys "`n"  # Ensure trailing newline

# Write to administrators_authorized_keys (for admin users)
Write-Host "Writing to administrators_authorized_keys..."
Set-Content $adminAuthKeys $hermesPubKey -NoNewline
Add-Content $adminAuthKeys "`n"  # Ensure trailing newline

# Step3: Fix permissions on BOTH files (CRITICAL)
Write-Host "=== Step3: Fix permissions ==="

# Remove inheritance and set proper ACLs for .ssh directory
icacls $sshDir /inheritance:r /grant:r "$($username):(OI)(CI)F" | Out-Null
icacls $sshDir /grant:r "SYSTEM:(OI)(CI)F" | Out-Null
icacls $sshDir /grant:r "Administrators:(OI)(CI)F" | Out-Null

# Fix authorized_keys permissions
icacls $authKeys /inheritance:r /grant:r "$($username):(F)" | Out-Null
icacls $authKeys /grant:r "SYSTEM:(F)" | Out-Null
icacls $authKeys /grant:r "Administrators:(F)" | Out-Null

# Fix administrators_authorized_keys permissions (MUST be restrictive)
icacls $adminAuthKeys /inheritance:r /grant:r "$($username):(F)" | Out-Null
icacls $adminAuthKeys /grant:r "SYSTEM:(F)" | Out-Null
icacls $adminAuthKeys /grant:r "Administrators:(F)" | Out-Null

Write-Host "Permissions set on both key files"

# Step4: Verify files
Write-Host "=== Step4: Verify key files ==="
Write-Host "authorized_keys exists: $(Test-Path $authKeys)"
Write-Host "administrators_authorized_keys exists: $(Test-Path $adminAuthKeys)"

Write-Host "authorized_keys content:"
Get-Content $authKeys | ForEach-Object { Write-Host $_ }

Write-Host "administrators_authorized_keys content:"
Get-Content $adminAuthKeys | ForEach-Object { Write-Host $_ }

# Step5: Restart sshd
Write-Host "=== Step5: Restart sshd ==="
Restart-Service sshd -Force
Start-Sleep 5
$sshdStatus = (Get-Service sshd).Status
Write-Host "sshd status: $sshdStatus"

# Step6: Verify port 22
Write-Host "=== Step6: Verify port 22 ==="
$port22 = netstat -an | findstr ":22"
if ($port22) {
  Write-Host "Port 22 listening: YES"
} else {
  Write-Host "WARNING: Port 22 not listening"
}

Write-Host "========================================="
Write-Host "SSH_ADMIN_AUTH_FIXED=True"
Write-Host "Username: $username"
Write-Host "authorized_keys: $authKeys"
Write-Host "administrators_authorized_keys: $adminAuthKeys"
Write-Host "sshd: $sshdStatus"
Write-Host "Tailscale IP: $(& 'C:\Program Files\Tailscale\Tailscale.exe' ip -4 2>&1)"
Write-Host "========================================="
Write-Host "Now EC2 should be able to SSH with Hermes key"
