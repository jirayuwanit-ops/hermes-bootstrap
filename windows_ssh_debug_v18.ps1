# windows_ssh_debug_v18.ps1
# Debug SSH key rejection + check sshd_config
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
Write-Host "SSH Debug v18"
Write-Host "========================================="

# Step 1: Check sshd_config for key-related settings
Write-Host "=== Step 1: sshd_config key settings ==="
$sshdConfig = "C:\ProgramData\ssh\sshd_config"
if (-not (Test-Path $sshdConfig)) {
  $sshdConfig = "C:\Program Files\OpenSSH-Win64\sshd_config"
}

if (Test-Path $sshdConfig) {
  Write-Host "sshd_config path: $sshdConfig"
  $configContent = Get-Content $sshdConfig -Raw
  
  $keyPatterns = @(
    "PubkeyAuthentication",
    "AuthorizedKeysFile",
    "AuthorizedKeysCommand",
    "PasswordAuthentication",
    "Match"
  )

  foreach ($pattern in $keyPatterns) {
    $matches = [regex]::Matches($configContent, "^[^#]*$pattern.*$", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    foreach ($match in $matches) {
      Write-Host $match.Value
    }
  }

  # Check for Match blocks that might override settings
  Write-Host "=== Match blocks in config ==="
  $matchBlocks = [regex]::Matches($configContent, "(?s)Match.*?\n\n")
  foreach ($block in $matchBlocks) {
    Write-Host $block.Value
    Write-Host "---"
  }
} else {
  Write-Host "ERROR: sshd_config not found"
}

# Step 2: Check Windows SSH log for recent auth attempts
Write-Host "=== Step 2: SSH auth log (last 50 lines) ==="
$sshLog = "C:\ProgramData\ssh\logs\sshd.log"
if (Test-Path $sshLog) {
  Get-Content $sshLog -Tail 50 | ForEach-Object { Write-Host $_ }
} else {
  Write-Host "Log not found at: $sshLog"
  # Try alternate log location
  $altLog = "C:\Windows\System32\OpenSSH\logs\sshd.log"
  if (Test-Path $altLog) {
    Write-Host "Found alternate log: $altLog"
    Get-Content $altLog -Tail 50 | ForEach-Object { Write-Host $_ }
  } else {
    Write-Host "No sshd log found"
  }
}

# Step 3: Verify authorized_keys files and permissions
Write-Host "=== Step 3: Verify key files ==="
$sshDir = "$env:USERPROFILE\.ssh"
$authKeys = "$sshDir\authorized_keys"
$adminAuthKeys = "$sshDir\administrators_authorized_keys"

Write-Host "authorized_keys exists: $(Test-Path $authKeys)"
Write-Host "administrators_authorized_keys exists: $(Test-Path $adminAuthKeys)"

if (Test-Path $authKeys) {
  $authContent = Get-Content $authKeys
  Write-Host "authorized_keys line count: $($authContent.Count)"
  Write-Host "authorized_keys bytes: $([System.IO.File]::ReadAllBytes($authKeys).Length)"
  
  # Check for BOM or encoding issues
  $bytes = [System.IO.File]::ReadAllBytes($authKeys)
  if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Host "WARNING: authorized_keys has UTF-8 BOM!"
  }
  if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
    Write-Host "WARNING: authorized_keys has UTF-16 BOM!"
  }
}

# Step 4: Check administrators_authorized_keys location (Windows may use different path)
Write-Host "=== Step 4: ProgramData SSH keys ==="
$programDataAuth = "C:\ProgramData\ssh\administrators_authorized_keys"
Write-Host "ProgramData administrators_authorized_keys exists: $(Test-Path $programDataAuth)"
if (Test-Path $programDataAuth) {
  Write-Host "Content:"
  Get-Content $programDataAuth | ForEach-Object { Write-Host $_ }
}

# Step 5: Check sshd effective config
Write-Host "=== Step 5: sshd effective config test ==="
$sshdTest = & "C:\Windows\System32\OpenSSH\sshd.exe" -t 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host "sshd config test FAILED:"
  Write-Host $sshdTest
} else {
  Write-Host "sshd config test: PASSED"
}

Write-Host "========================================="
Write-Host "SSH_DEBUG_DONE=True"
Write-Host "========================================="
