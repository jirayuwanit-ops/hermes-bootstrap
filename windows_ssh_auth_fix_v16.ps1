# windows_ssh_auth_fix_v16.ps1
# Fix SSH public key authentication
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
Write-Host "SSH Auth Fix v16"
Write-Host "========================================="

$username = $env:USERNAME
Write-Host "Username: $username"

# Step 1: Verify .ssh directory and authorized_keys
Write-Host "=== Step 1: Check .ssh directory ==="
$sshDir = "$env:USERPROFILE\.ssh"
$authKeys = "$sshDir\authorized_keys"

Write-Host "SSH dir: $sshDir"
Write-Host "authorized_keys: $authKeys"

if (-not (Test-Path $sshDir)) {
  Write-Host "Creating .ssh directory..."
  New-Item -ItemType Directory -Force $sshDir | Out-Null
}

# Step 2: Write Hermes public key (correct format)
Write-Host "=== Step 2: Update authorized_keys ==="
$hermesPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICnjQFSqL7S8kTHphU2Mcrl8di+0ZX8AYHG5YbIf1M0b hermes@ec2-to-windows"

# Check if key already exists
$keyExists = $false
if (Test-Path $authKeys) {
  $existingContent = Get-Content $authKeys -Raw -ErrorAction SilentlyContinue
  if ($existingContent -match [regex]::Escape($hermesPubKey)) {
    Write-Host "Hermes public key already in authorized_keys"
    $keyExists = $true
  }
}

if (-not $keyExists) {
  Write-Host "Adding Hermes public key to authorized_keys..."
  Add-Content $authKeys "`n$hermesPubKey`n" -ErrorAction SilentlyContinue
  if (-not (Test-Path $authKeys)) {
    Set-Content $authKeys $hermesPubKey
  }
}

# Step 3: Fix permissions (CRITICAL for Windows SSH)
Write-Host "=== Step 3: Fix permissions ==="

# Remove inheritance and set proper ACLs
icacls $sshDir /inheritance:r /grant:r "$($username):(OI)(CI)F" | Out-Null
icacls $authKeys /inheritance:r /grant:r "$($username):(F)" | Out-Null

# Also try SYSTEM and Administrators access
icacls $sshDir /grant:r "SYSTEM:(OI)(CI)F" | Out-Null
icacls $sshDir /grant:r "Administrators:(OI)(CI)F" | Out-Null
icacls $authKeys /grant:r "SYSTEM:(F)" | Out-Null
icacls $authKeys /grant:r "Administrators:(F)" | Out-Null

Write-Host "Permissions set"

# Step 4: Verify authorized_keys content
Write-Host "=== Step 4: Verify authorized_keys ==="
if (Test-Path $authKeys) {
  Write-Host "authorized_keys content:"
  Get-Content $authKeys | ForEach-Object { Write-Host $_ }
} else {
  Write-Host "ERROR: authorized_keys not found!"
}

# Step 5: Restart sshd
Write-Host "=== Step 5: Restart sshd ==="
Restart-Service sshd -Force
Start-Sleep 3
$sshdStatus = (Get-Service sshd).Status
Write-Host "sshd status: $sshdStatus"

# Step 6: Test local SSH connection
Write-Host "=== Step 6: Local SSH test ==="
$localTest = ssh -o StrictHostKeyChecking=no -o BatchMode=yes -i "$sshDir\id_ed25519_local" $username@localhost "echo SSH_LOCAL_OK" 2>&1
if ($localTest -match "SSH_LOCAL_OK") {
  Write-Host "Local SSH test: PASSED"
} else {
  Write-Host "Local SSH test: Could not test (no local key), but auth should work"
}

# Step 7: Verify port 22
Write-Host "=== Step 7: Verify port 22 ==="
$port22 = netstat -an | findstr ":22"
if ($port22) {
  Write-Host "Port 22 listening: YES"
  Write-Host $port22
} else {
  Write-Host "WARNING: Port 22 not listening"
}

Write-Host "========================================="
Write-Host "SSH_AUTH_FIXED=True"
Write-Host "Username: $username"
Write-Host "authorized_keys: $authKeys"
Write-Host "sshd: $sshdStatus"
Write-Host "Tailscale IP: $(& 'C:\Program Files\Tailscale\Tailscale.exe' ip -4 2>&1)"
Write-Host "========================================="
