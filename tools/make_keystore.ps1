# Creates the upload keystore that signs every Play release.
#
# PowerShell version of tools/make_keystore.sh, for running directly in a
# normal PowerShell window:
#
#     cd C:\Users\hp\Desktop\app-development
#     powershell -ExecutionPolicy Bypass -File tools\make_keystore.ps1
#
# The password is read with Read-Host -AsSecureString, so it is never echoed
# and never lands in your PowerShell history.
#
# IMPORTANT: back up android\upload-keystore.jks and android\key.properties
# somewhere off this machine. Lose them and this app can never be updated on
# Play again — Play identifies an app by its signature and there is no
# recovery.

$ErrorActionPreference = 'Stop'

$root  = Split-Path -Parent $PSScriptRoot
$store = Join-Path $root 'android\upload-keystore.jks'
$props = Join-Path $root 'android\key.properties'

if (Test-Path $store) {
    Write-Host "X $store already exists." -ForegroundColor Red
    Write-Host "  Refusing to overwrite it - replacing a keystore makes every"
    Write-Host "  previous release un-updatable. Delete it yourself if sure."
    exit 1
}

# keytool ships with the JDK. Look in the usual places rather than assuming
# JAVA_HOME is set - a missing JAVA_HOME is not a missing JDK.
$keytool = $null
$cmd = Get-Command keytool -ErrorAction SilentlyContinue
if ($cmd) { $keytool = $cmd.Source }

if (-not $keytool) {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += (Join-Path $env:JAVA_HOME 'bin\keytool.exe') }
    $candidates += Get-ChildItem 'C:\Program Files\Eclipse Adoptium\*\bin\keytool.exe' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    $candidates += Get-ChildItem 'C:\Program Files\Java\*\bin\keytool.exe'             -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    $candidates += 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { $keytool = $c; break }
    }
}

if (-not $keytool) {
    Write-Host "X Could not find keytool. Install a JDK, or set JAVA_HOME." -ForegroundColor Red
    exit 1
}
Write-Host "-> using $keytool"

$cn = Read-Host 'Your name or company (shown in the certificate)'
if ([string]::IsNullOrWhiteSpace($cn)) { $cn = 'Who Pays' }

# Asked twice because a typo here is unrecoverable later.
$p1 = Read-Host 'Choose a keystore password (min 6 chars)' -AsSecureString
$p2 = Read-Host 'Type it again' -AsSecureString

$b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1)
$b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2)
$pw1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b1)
$pw2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b2)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)

if ($pw1 -ne $pw2)    { Write-Host "X They don't match." -ForegroundColor Red; exit 1 }
if ($pw1.Length -lt 6) { Write-Host "X Too short - keytool requires 6+." -ForegroundColor Red; exit 1 }

# 10000 days: Play requires the key to outlive 2033, and an expired key is as
# unusable as a lost one.
& $keytool -genkeypair `
    -alias upload `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -keystore $store `
    -storetype JKS `
    -storepass $pw1 -keypass $pw1 `
    -dname "CN=$cn, OU=, O=, L=, S=, C=IN"

if ($LASTEXITCODE -ne 0) {
    Write-Host "X keytool failed." -ForegroundColor Red
    exit 1
}

@(
    "storePassword=$pw1"
    "keyPassword=$pw1"
    "keyAlias=upload"
    "storeFile=upload-keystore.jks"
) | Out-File -FilePath $props -Encoding ascii

$pw1 = $null; $pw2 = $null

Write-Host ''
Write-Host 'OK Created:' -ForegroundColor Green
Write-Host "    $store"
Write-Host "    $props"
Write-Host ''
Write-Host 'Release builds will now be signed with it automatically.'
Write-Host ''
Write-Host '!! Back BOTH files up off this machine before you publish.' -ForegroundColor Yellow
Write-Host '   Lose them and this app can never be updated again.'
