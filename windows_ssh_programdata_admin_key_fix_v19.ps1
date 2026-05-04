# windows_ssh_programdata_admin_key_fix_v19.ps1
# Fix: Write Hermes key to C:\ProgramData\ssh\administrators_authorized_keys (correct path for Windows Admin users)
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
Write-Host "SSH ProgramData Admin Key Fix v19"
Write-Host "========================================="

$hermesKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICnjQFSqL7S8kTHphU2Mcrl8di+0ZX8AYHG5YbIf1M0b hermes@ec2-to-windows"

# Step 1: Write to C:\ProgramData\ssh\administrators_authorized_keys (CORRECT path)
Write-Host "=== Step 1: Write ProgramData administrators_authorized_keys ==="
$programDataSsh = "C:\ProgramData\ssh"
$adminAuthKeys = "$programDataSsh\administrators_authorized_keys"

New-Item -ItemType Directory -Force $programDataSsh | Out-Null

# Write with UTF-8 NO BOM
[System.IO.File]::WriteAllText($adminAuthKeys, "$hermesKey`r`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "Written to: $adminAuthKeys"

# Verify content
$verifyContent = Get-Content $adminAuthKeys -Raw
Write-Host "Content: $verifyContent"

# Step 2: Set strict permissions (no inheritance)
Write-Host "=== Step 2: Set permissions ==="
icacls $adminAuthKeys /inheritance:r | Out-Null
icacls $adminAuthKeys /grant "Administrators:F" | Out-Null
icacls $adminAuthKeys /grant "SYSTEM:F" | Out-Null
Write-Host "Permissions: Administrators:F, SYSTEM:F, no inheritance"

# Step 3: Also ensure user-profile authorized_keys still exists
Write-Host "=== Step 3: Ensure user authorized_keys ==="
$userAuthKeys = "$env:USERPROFILE\.ssh\authorized_keys"
if (-not (Test-Path $userAuthKeys)) {
  New-Item -ItemType Directory -Force "$env:USERPROFILE\.ssh" | Out-Null
  [System.IO.File]::WriteAllText($userAuthKeys, "$hermesKey`r`n", [System.Text.UTF8Encoding]::new($false))
  Write-Host "Also created: $userAuthKeys"
} else {
  Write-Host "User authorized_keys already exists: $userAuthKeys"
}

# Step 4: sshd config test
Write-Host "=== Step 4: sshd config test ==="
$sshdExe = "C:\Windows\System32\OpenSSH\sshd.exe"
if (Test-Path $sshdExe) {
  $testOutput = & $sshdExe -t 2>&1
  if ($LASTEXITCODE -eq 0) {
    Write-Host "sshd config test: PASSED"
  } else {
    Write-Host "sshd config test: FAILED"
    Write-Host $testOutput
  }
} else {
  Write-Host "sshd.exe not found at expected path, skipping config test"
}

# Step 5: Restart sshd
Write-Host "=== Step 5: Restart sshd ==="
Restart-Service sshd -Force
Start-Sleep 5
$sshdStatus = (Get-Service sshd).Status
Write-Host "sshd status: $sshdStatus"

# Step 6: Verify port 22
$port22 = netstat -an | findstr ":22"
Write-Host "Port 22 listening: $(if($port22){'YES'}else{'NO'})"

Write-Host "========================================="
Write-Host "SSH_PROGRAMDATA_ADMIN_KEY_FIXED=True"
Write-Host "Path: $adminAuthKeys"
Write-Host "sshd: $sshdStatus"
Write-Host "========================================="
