# WinGetLookup

[![PowerShell Gallery](https://img.shields.io/badge/PowerShell%20Gallery-v2.0.0--alpha1-orange)](https://www.powershellgallery.com/packages/WinGetLookup)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/powershell/)

> ⚠️ **ALPHA RELEASE** - This is version 2.0.0-alpha1. APIs may change before the final 2.0.0 release.

A PowerShell module to query the WinGet (Windows Package Manager) repository with **high fidelity to WinGet's internal operations** — without requiring WinGet to be installed locally.

![WinGetLookup](icon.png)

## Features

- 🔍 **API-Based Lookups** - Query WinGet repository via REST API (no WinGet CLI required)
- 🎯 **Smart Matching** - Hybrid scoring using API SearchScore + client-side validation
- 🏗️ **True Architecture Detection** - Actual x86/x64/arm/arm64 data from manifest (not heuristics)
- 📦 **InstallerType Awareness** - Know if you're getting MSI, EXE, MSIX, Inno, portable, etc.
- 🔐 **Scope Detection** - See if user or machine installation is available
- 📊 **Version Comparison** - Compare and sort WinGet-style version strings
- 🔗 **ProductCode Correlation** - Find WinGet packages by MSI ProductCode GUID
- ⚡ **Session Caching** - Intelligent caching with retry logic and exponential backoff
- 🏢 **Publisher Filtering** - Server-side publisher filtering for efficiency
- 🔧 **Pipeline Support** - Full PowerShell pipeline integration throughout

## What's New in v2.0.0-alpha1

> ⚠️ **ALPHA RELEASE** - This is a pre-release version for testing. Please report issues on GitHub.

Version 2.0.0-alpha1 is a major refactor focused on **accuracy and completeness**:

| Feature | Before (v1.x) | After (v2.0) |
|---------|---------------|--------------|
| 64-bit detection | Regex heuristics + hardcoded list | Actual manifest `Installers[].Architecture` data |
| Installer types | Not available | Full exposure (msi, exe, msix, inno, nullsoft, portable, etc.) |
| Installation scope | Not available | User vs machine scope from manifest |
| Version comparison | Not available | `Compare-WinGetVersion`, `Get-WinGetLatestVersion` |
| ProductCode search | Not available | `Find-WinGetPackageByProductCode` for MSI correlation |
| API resilience | Single attempt | Retry with exponential backoff (429, 5xx handling) |
| Publisher filter | Client-side only | Server-side API parameter |
| Cache keys | Search term only | Full parameter awareness (term + publisher + id) |

## Installation

### From PowerShell Gallery (Recommended)

```powershell
Install-Module -Name WinGetLookup -Scope CurrentUser
```

### Update Existing Installation

```powershell
Update-Module -Name WinGetLookup
```

### Manual Installation

```powershell
# Clone and install
git clone https://github.com/Ringosystems/WinGetLookup.git
Copy-Item -Path .\WinGetLookup -Destination "$env:USERPROFILE\Documents\PowerShell\Modules\" -Recurse
Import-Module WinGetLookup
```

## Requirements

- **PowerShell 5.1** (Windows PowerShell) or **PowerShell 7+** (PowerShell Core)
- Internet connectivity for API access
- No WinGet installation required for API-based functions

### Supported Platforms

| Platform | Version |
|----------|---------|
| Windows 10 | 1709 (build 16299) or later |
| Windows 11 | All versions |
| Windows Server 2019 | Build 17763 or later |
| Windows Server 2022 | All versions |

---

## Quick Start

```powershell
Import-Module WinGetLookup

# Check if an application exists in WinGet
Test-WinGetPackage -DisplayName "7-Zip"
# Returns: 1 (found) or 0 (not found)

# Get comprehensive package information
Get-WinGetPackageInfo -DisplayName "Visual Studio Code"

# Check for 64-bit availability using actual manifest data
Test-WinGetPackage -DisplayName "WinRAR" -Require64Bit

# Compare versions
Compare-WinGetVersion -Version1 "24.09" -Version2 "24.10"
# Returns: -1 (Version1 is older)

# Find WinGet package by MSI ProductCode
Find-WinGetPackageByProductCode -ProductCode "{AC76BA86-7AD7-1033-7B44-AC0F074E4100}"
```

---

## Functions Reference

### Test-WinGetPackage

Tests if an application package exists in the WinGet repository.

```powershell
# Basic availability check
Test-WinGetPackage -DisplayName "VLC"
# Returns: 1

# Filter by publisher (applied at API level for efficiency)
Test-WinGetPackage -DisplayName "PuTTY" -Publisher "Simon Tatham"
# Returns: 1 (specifically Simon Tatham's PuTTY, not MTPuTTY)

# Exact package ID match
Test-WinGetPackage -DisplayName "Chrome" -PackageId "Google.Chrome"
# Returns: 1

# Require 64-bit version (uses actual manifest architecture data)
Test-WinGetPackage -DisplayName "Adobe Acrobat Reader" -Require64Bit
# Returns: 1 if x64 or arm64 installer exists in manifest

# Pipeline support for batch checking
@("7-Zip", "Notepad++", "FakeApp123", "VLC") | ForEach-Object {
    [PSCustomObject]@{
        Application = $_
        Available   = Test-WinGetPackage -DisplayName $_
    }
} | Format-Table -AutoSize

# Output:
# Application   Available
# -----------   ---------
# 7-Zip                 1
# Notepad++             1
# FakeApp123            0
# VLC                   1
```

**Returns:** `1` if package is found (and meets requirements), `0` otherwise.

---

### Get-WinGetPackageInfo

Retrieves comprehensive package information including installer metadata.

```powershell
# Get full package details
$pkg = Get-WinGetPackageInfo -DisplayName "7-Zip"
$pkg | Format-List

# Output:
# Id                : 7zip.7zip
# Name              : 7-Zip
# Publisher         : Igor Pavlov
# Description       : 7-Zip is a file archiver with a high compression ratio.
# Homepage          : https://www.7-zip.org/
# License           : LGPL-2.1-or-later
# Tags              : archive, compression, zip, 7z
# Versions          : 24.09, 24.08, 24.07, 24.06, ...
# LatestVersion     : 24.09
# Architectures     : x86, x64, arm64
# InstallerTypes    : exe, msi
# AvailableScopes   : machine
# Has64BitInstaller : True
# Found             : True

# Check what installer types are available
$pkg = Get-WinGetPackageInfo -DisplayName "Microsoft Teams"
if ($pkg.InstallerTypes -match 'msix') {
    Write-Host "MSIX installer available - good for Intune!"
}

# Check available architectures before deployment
$pkg = Get-WinGetPackageInfo -DisplayName "Zoom"
Write-Host "Available architectures: $($pkg.Architectures)"
# Output: Available architectures: x86, x64, arm64

# Filter by publisher for disambiguation
$pkg = Get-WinGetPackageInfo -DisplayName "Python" -Publisher "Python Software Foundation"
Write-Host "Package ID: $($pkg.Id)"
# Output: Package ID: Python.Python.3.12

# Batch lookup with pre-warming for performance
$apps = @("7-Zip", "Notepad++", "VLC", "WinRAR", "FileZilla")
Initialize-WinGetPackageCache -SearchTerms $apps

$results = $apps | ForEach-Object {
    Get-WinGetPackageInfo -DisplayName $_
} | Select-Object Name, Id, Architectures, InstallerTypes, Has64BitInstaller

$results | Format-Table -AutoSize
```

**Output Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `Id` | String | WinGet package identifier (e.g., "7zip.7zip") |
| `Name` | String | Display name |
| `Publisher` | String | Publisher name |
| `Description` | String | Package description |
| `Homepage` | String | Product/publisher URL |
| `License` | String | License type |
| `Tags` | String | Comma-separated tags |
| `Versions` | String | Comma-separated available versions |
| `LatestVersion` | String | Highest version (computed) |
| `Architectures` | String | Available architectures (x86, x64, arm, arm64) |
| `InstallerTypes` | String | Available types (msi, exe, msix, inno, nullsoft, portable, etc.) |
| `AvailableScopes` | String | Installation scopes (user, machine) |
| `Has64BitInstaller` | Boolean | True if x64 or arm64 installer exists |
| `Found` | Boolean | True if package was found |

---

### Compare-WinGetVersion

Compares two WinGet-style version strings using WinGet's comparison logic.

```powershell
# Basic comparison
Compare-WinGetVersion -Version1 "1.0.0" -Version2 "1.0.1"
# Returns: -1 (Version1 is older)

Compare-WinGetVersion -Version1 "2.0" -Version2 "1.9.9"
# Returns: 1 (Version1 is newer)

Compare-WinGetVersion -Version1 "24.09" -Version2 "24.09"
# Returns: 0 (equal)

# Works with various version formats
Compare-WinGetVersion "v1.2.3" "1.2.4"      # Handles 'v' prefix
Compare-WinGetVersion "2024.01.15" "2024.02.01"  # Date-based versions
Compare-WinGetVersion "24.09" "24.10"       # Short versions

# Practical example: Check if installed version needs update
$installedVersion = "23.08"
$pkg = Get-WinGetPackageInfo -DisplayName "7-Zip"

if ($pkg.Found) {
    $comparison = Compare-WinGetVersion -Version1 $installedVersion -Version2 $pkg.LatestVersion
    
    switch ($comparison) {
        -1 { Write-Host "Update available: $installedVersion → $($pkg.LatestVersion)" -ForegroundColor Yellow }
         0 { Write-Host "Already at latest version: $installedVersion" -ForegroundColor Green }
         1 { Write-Host "Installed version is newer than repository?!" -ForegroundColor Red }
    }
}
# Output: Update available: 23.08 → 24.09
```

**Returns:** `-1` if Version1 < Version2, `0` if equal, `1` if Version1 > Version2

---

### Get-WinGetLatestVersion

Returns the highest version from an array of version strings.

```powershell
# Get latest from array
Get-WinGetLatestVersion -Versions @("1.0", "2.0", "1.5.3", "1.9.9")
# Returns: 2.0

# Pipeline support
@("24.08", "24.09", "24.07", "24.10") | Get-WinGetLatestVersion
# Returns: 24.10

# Use with package info
$pkg = Get-WinGetPackageInfo -DisplayName "Python"
$versions = $pkg.Versions -split ', '
$latest = Get-WinGetLatestVersion -Versions $versions
Write-Host "Latest Python version: $latest"

# Find packages with versions older than a threshold
$apps = @("7-Zip", "Notepad++", "VLC")
$minYear = "24.01"

foreach ($app in $apps) {
    $pkg = Get-WinGetPackageInfo -DisplayName $app
    if ($pkg.Found -and $pkg.LatestVersion) {
        $cmp = Compare-WinGetVersion -Version1 $pkg.LatestVersion -Version2 $minYear
        if ($cmp -lt 0) {
            Write-Host "$($pkg.Name) latest version ($($pkg.LatestVersion)) is older than $minYear" -ForegroundColor Yellow
        }
    }
}
```

---

### Test-WinGet64BitAvailable

Definitively checks 64-bit availability using the local WinGet CLI.

```powershell
# Check if package has x64 installer (requires WinGet CLI)
Test-WinGet64BitAvailable -PackageId "RARLab.WinRAR"
# Returns: $true

Test-WinGet64BitAvailable -PackageId "Adobe.Acrobat.Reader.32-bit"
# Returns: $false (this specific package is 32-bit only)

# Pipeline from package lookup
$pkg = Get-WinGetPackageInfo -DisplayName "WinRAR"
if ($pkg.Found) {
    $has64 = Test-WinGet64BitAvailable -PackageId $pkg.Id
    Write-Host "$($pkg.Name): CLI confirms 64-bit = $has64"
}

# Batch check with progress
$packages = @("7zip.7zip", "Notepad++.Notepad++", "VideoLAN.VLC", "WinSCP.WinSCP")
$results = $packages | ForEach-Object {
    [PSCustomObject]@{
        PackageId = $_
        Has64Bit  = Test-WinGet64BitAvailable -PackageId $_
    }
}
$results | Format-Table -AutoSize
```

**Note:** Requires WinGet CLI to be installed. Returns `$false` if CLI is unavailable.

---

### Get-WinGet64BitPackageId

Finds the 64-bit package ID, handling both same-package and separate-package scenarios.

```powershell
# Scenario 1: Same package has both architectures
Get-WinGet64BitPackageId -PackageId "7zip.7zip"
# Returns: 7zip.7zip (same package has x64 installer)

# Scenario 2: Separate 32-bit and 64-bit packages
Get-WinGet64BitPackageId -PackageId "Adobe.Acrobat.Reader.32-bit"
# Returns: Adobe.Acrobat.Reader.64-bit

# Scenario 3: No 64-bit available
Get-WinGet64BitPackageId -PackageId "SomeLegacy.App.x86"
# Returns: $null

# Practical migration workflow
$installedApps = @(
    [PSCustomObject]@{ Name = "Adobe Reader"; PackageId = "Adobe.Acrobat.Reader.32-bit" },
    [PSCustomObject]@{ Name = "7-Zip"; PackageId = "7zip.7zip" },
    [PSCustomObject]@{ Name = "WinRAR"; PackageId = "RARLab.WinRAR" }
)

$migrationPlan = $installedApps | ForEach-Object {
    $x64Id = Get-WinGet64BitPackageId -PackageId $_.PackageId
    [PSCustomObject]@{
        Application     = $_.Name
        CurrentId       = $_.PackageId
        TargetId        = if ($x64Id) { $x64Id } else { "N/A" }
        MigrationAction = if ($x64Id -eq $_.PackageId) { "Reinstall (same pkg)" }
                          elseif ($x64Id) { "Upgrade to 64-bit" }
                          else { "No 64-bit available" }
    }
}

$migrationPlan | Format-Table -AutoSize

# Output:
# Application   CurrentId                      TargetId                       MigrationAction
# -----------   ---------                      --------                       ---------------
# Adobe Reader  Adobe.Acrobat.Reader.32-bit    Adobe.Acrobat.Reader.64-bit    Upgrade to 64-bit
# 7-Zip         7zip.7zip                      7zip.7zip                      Reinstall (same pkg)
# WinRAR        RARLab.WinRAR                  RARLab.WinRAR                  Reinstall (same pkg)
```

---

### Find-WinGetPackageByProductCode

Searches for a WinGet package using an MSI ProductCode GUID.

```powershell
# Search by ProductCode (with or without braces)
Find-WinGetPackageByProductCode -ProductCode "{AC76BA86-7AD7-1033-7B44-AC0F074E4100}"
# Or without braces:
Find-WinGetPackageByProductCode -ProductCode "AC76BA86-7AD7-1033-7B44-AC0F074E4100"

# Output:
# Name        : Adobe Acrobat Reader DC
# Id          : Adobe.Acrobat.Reader.64-bit
# Version     : 24.002.20933
# Source      : winget
# ProductCode : {AC76BA86-7AD7-1033-7B44-AC0F074E4100}

# Correlate installed MSI products with WinGet packages
$msiProducts = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" |
    Where-Object { $_.PSChildName -match '^\{[A-F0-9-]+\}$' } |
    Select-Object -First 10 DisplayName, PSChildName

$correlations = $msiProducts | ForEach-Object {
    $wingetPkg = Find-WinGetPackageByProductCode -ProductCode $_.PSChildName
    [PSCustomObject]@{
        InstalledName = $_.DisplayName
        ProductCode   = $_.PSChildName
        WinGetId      = if ($wingetPkg) { $wingetPkg.Id } else { "Not in WinGet" }
        WinGetVersion = if ($wingetPkg) { $wingetPkg.Version } else { $null }
    }
}

$correlations | Format-Table -AutoSize

# Use case: Find upgrade path for installed MSI
$productCode = "{7B5AA67E-FEA0-40F8-8C86-C514A074E3C0}"  # Example
$wingetPkg = Find-WinGetPackageByProductCode -ProductCode $productCode

if ($wingetPkg) {
    Write-Host "Found WinGet package: $($wingetPkg.Id) v$($wingetPkg.Version)"
    Write-Host "Upgrade command: winget upgrade --id $($wingetPkg.Id)"
} else {
    Write-Host "No WinGet package found for this ProductCode"
}
```

**Note:** Requires WinGet CLI to be installed.

---

### Cache Management Functions

#### Clear-WinGetCache

```powershell
# Clear all cached data (package searches + manifest data)
Clear-WinGetCache

# Use case: Force fresh data after WinGet repository update
Clear-WinGetCache
$pkg = Get-WinGetPackageInfo -DisplayName "SomeApp"  # Fresh API call
```

#### Get-WinGetCacheStatistics

```powershell
# View cache performance
Get-WinGetCacheStatistics | Format-List

# Output:
# PackageCacheEntries  : 15
# ManifestCacheEntries : 8
# CacheHits            : 42
# CacheMisses          : 23
# TotalRequests        : 65
# EfficiencyPct        : 64.62
# ApiCallsSaved        : 42

# Monitor cache during batch operations
$apps = @("7-Zip", "VLC", "Firefox", "Chrome", "Notepad++")

# First pass - all cache misses
$apps | ForEach-Object { $null = Get-WinGetPackageInfo $_ }
Write-Host "After first pass:"
Get-WinGetCacheStatistics | Select-Object CacheHits, CacheMisses

# Second pass - all cache hits
$apps | ForEach-Object { $null = Get-WinGetPackageInfo $_ }
Write-Host "After second pass:"
Get-WinGetCacheStatistics | Select-Object CacheHits, CacheMisses
```

#### Initialize-WinGetPackageCache

```powershell
# Pre-warm cache for known application list
$commonApps = @(
    "7-Zip", "Notepad++", "VLC", "Firefox", "Chrome",
    "Visual Studio Code", "Git", "Python", "Node.js", "WinRAR"
)

Initialize-WinGetPackageCache -SearchTerms $commonApps -ThrottleDelayMs 100

# Check cache status
Get-WinGetCacheStatistics

# Now all lookups are instant (from cache)
$commonApps | ForEach-Object {
    $pkg = Get-WinGetPackageInfo $_
    Write-Host "$($pkg.Name): $($pkg.LatestVersion)"
}

# Pre-warm with publisher filter
Initialize-WinGetPackageCache -SearchTerms @("Office", "Teams", "Edge") -Publisher "Microsoft"
```

---

## Real-World Use Cases

### 1. Application Inventory Assessment for Intune Migration

```powershell
# Assess which installed applications can be migrated to WinGet/Intune
$installedApps = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                                  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" |
    Where-Object { $_.DisplayName -and $_.Publisher } |
    Select-Object DisplayName, DisplayVersion, Publisher, @{N='Architecture';E={
        if ($_.PSPath -match 'WOW6432Node') { 'x86' } else { 'x64' }
    }}

# Pre-warm cache for efficiency
Initialize-WinGetPackageCache -SearchTerms ($installedApps.DisplayName | Select-Object -Unique)

# Generate migration assessment
$assessment = $installedApps | ForEach-Object {
    $pkg = Get-WinGetPackageInfo -DisplayName $_.DisplayName
    
    [PSCustomObject]@{
        Application      = $_.DisplayName
        InstalledVersion = $_.DisplayVersion
        InstalledArch    = $_.Architecture
        InWinGet         = $pkg.Found
        WinGetId         = $pkg.Id
        WinGetVersion    = $pkg.LatestVersion
        Has64Bit         = $pkg.Has64BitInstaller
        InstallerTypes   = $pkg.InstallerTypes
        CanUpgrade       = if ($pkg.Found -and $_.DisplayVersion -and $pkg.LatestVersion) {
                              (Compare-WinGetVersion $_.DisplayVersion $pkg.LatestVersion) -lt 0
                          } else { $null }
    }
}

# Summary report
$assessment | Group-Object InWinGet | ForEach-Object {
    Write-Host "$($_.Name): $($_.Count) applications"
}

# Export for review
$assessment | Export-Csv -Path "WinGet_Migration_Assessment.csv" -NoTypeInformation

# Show applications ready for 64-bit upgrade
$assessment | Where-Object { $_.InstalledArch -eq 'x86' -and $_.Has64Bit } |
    Select-Object Application, WinGetId, InstallerTypes |
    Format-Table -AutoSize
```

### 2. 32-bit to 64-bit Migration Planning

```powershell
# Find all 32-bit applications and plan 64-bit migration
$x86Apps = Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" |
    Where-Object { $_.DisplayName }

$migrationPlan = $x86Apps | ForEach-Object {
    $pkg = Get-WinGetPackageInfo -DisplayName $_.DisplayName
    
    if ($pkg.Found) {
        $x64PackageId = Get-WinGet64BitPackageId -PackageId $pkg.Id
        
        [PSCustomObject]@{
            Application    = $_.DisplayName
            CurrentVersion = $_.DisplayVersion
            WinGetId       = $pkg.Id
            X64PackageId   = $x64PackageId
            Action         = if (-not $x64PackageId) { "❌ No 64-bit available" }
                            elseif ($x64PackageId -eq $pkg.Id) { "✅ Same package (has x64)" }
                            else { "🔄 Migrate to: $x64PackageId" }
            InstallCmd     = if ($x64PackageId) { "winget install --id $x64PackageId --architecture x64" } else { $null }
        }
    }
}

# Display migration plan
$migrationPlan | Where-Object { $_.Action } | Format-Table Application, Action, X64PackageId -AutoSize

# Generate installation script
$migrationPlan | Where-Object { $_.InstallCmd } | ForEach-Object {
    "# $($_.Application)"
    $_.InstallCmd
    ""
} | Out-File -FilePath "Migration_Install_Script.ps1"
```

### 3. SCCM/Intune Package Validation

```powershell
# Validate application list before creating deployment packages
$deploymentList = @(
    @{ Name = "7-Zip"; RequiredArch = "x64"; RequiredType = "msi" },
    @{ Name = "Notepad++"; RequiredArch = "x64"; RequiredType = "exe" },
    @{ Name = "Adobe Acrobat Reader"; RequiredArch = "x64"; RequiredType = "exe" },
    @{ Name = "VLC"; RequiredArch = "x64"; RequiredType = $null }  # Any type OK
)

$validation = $deploymentList | ForEach-Object {
    $pkg = Get-WinGetPackageInfo -DisplayName $_.Name
    
    $archOK = if ($_.RequiredArch) {
        $pkg.Architectures -match $_.RequiredArch
    } else { $true }
    
    $typeOK = if ($_.RequiredType) {
        $pkg.InstallerTypes -match $_.RequiredType
    } else { $true }
    
    [PSCustomObject]@{
        Application     = $_.Name
        WinGetId        = $pkg.Id
        RequiredArch    = $_.RequiredArch
        AvailableArch   = $pkg.Architectures
        ArchValid       = $archOK
        RequiredType    = $_.RequiredType
        AvailableTypes  = $pkg.InstallerTypes
        TypeValid       = $typeOK
        OverallStatus   = if ($archOK -and $typeOK) { "✅ Ready" } else { "❌ Check Config" }
    }
}

$validation | Format-Table Application, OverallStatus, AvailableArch, AvailableTypes -AutoSize
```

### 4. Version Compliance Reporting

```powershell
# Check if installed versions meet minimum requirements
$minimumVersions = @{
    "7-Zip" = "24.00"
    "Notepad++" = "8.6"
    "VLC" = "3.0.20"
    "Git" = "2.43"
    "Python" = "3.12"
}

$complianceReport = $minimumVersions.GetEnumerator() | ForEach-Object {
    $app = $_.Key
    $minVersion = $_.Value
    $pkg = Get-WinGetPackageInfo -DisplayName $app
    
    if ($pkg.Found -and $pkg.LatestVersion) {
        $meetsMinimum = (Compare-WinGetVersion $pkg.LatestVersion $minVersion) -ge 0
        
        [PSCustomObject]@{
            Application      = $app
            MinimumRequired  = $minVersion
            LatestAvailable  = $pkg.LatestVersion
            MeetsRequirement = if ($meetsMinimum) { "✅ Yes" } else { "❌ No" }
            Gap              = if (-not $meetsMinimum) { "Need $minVersion, only $($pkg.LatestVersion) available" } else { $null }
        }
    }
}

$complianceReport | Format-Table -AutoSize
```

### 5. MSI ProductCode Inventory Correlation

```powershell
# Correlate all MSI installations with WinGet packages for upgrade management
$msiInstalls = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" |
    Where-Object { $_.PSChildName -match '^\{[A-F0-9-]+\}$' } |
    Select-Object DisplayName, DisplayVersion, Publisher, 
                  @{N='ProductCode';E={$_.PSChildName}}

Write-Host "Correlating $($msiInstalls.Count) MSI installations with WinGet..." -ForegroundColor Cyan

$correlation = $msiInstalls | ForEach-Object {
    $wingetMatch = Find-WinGetPackageByProductCode -ProductCode $_.ProductCode
    
    [PSCustomObject]@{
        InstalledApp    = $_.DisplayName
        InstalledVer    = $_.DisplayVersion
        ProductCode     = $_.ProductCode
        WinGetMatch     = if ($wingetMatch) { $wingetMatch.Id } else { $null }
        WinGetVersion   = if ($wingetMatch) { $wingetMatch.Version } else { $null }
        UpgradeAvail    = if ($wingetMatch -and $_.DisplayVersion) {
                             (Compare-WinGetVersion $_.DisplayVersion $wingetMatch.Version) -lt 0
                         } else { $null }
    }
}

# Summary
$matched = ($correlation | Where-Object { $_.WinGetMatch }).Count
$total = $correlation.Count
Write-Host "`n$matched of $total MSI products found in WinGet ($([math]::Round($matched/$total*100,1))%)" -ForegroundColor Green

# Show upgradeable applications
$correlation | Where-Object { $_.UpgradeAvail -eq $true } | 
    Select-Object InstalledApp, InstalledVer, WinGetVersion |
    Format-Table -AutoSize
```

---

## How It Works

WinGetLookup uses the [winget.run](https://winget.run) REST API to query the WinGet package repository. This provides:

1. **No Local WinGet Required** - Works on systems without WinGet installed
2. **Actual Manifest Data** - Returns real architecture, installer type, and scope information
3. **Faster Queries** - API calls with caching are faster than repeated CLI operations
4. **Automation-Friendly** - No interactive prompts or UI elements

### API Endpoints Used

| Endpoint | Purpose |
|----------|---------|
| `/v2/packages?name=...` | Package search with smart matching |
| `/v2/packages/{Publisher}/{Package}` | Full manifest data retrieval |

### Caching Strategy

- **Package Cache**: Search results cached by full query parameters (term + publisher + id)
- **Manifest Cache**: Full package manifests cached by package ID
- **Automatic Retry**: Failed requests retry with exponential backoff (500ms → 1s → 2s)
- **Rate Limit Handling**: 429 responses trigger automatic retry with backoff

---

## Breaking Changes from v1.x

| Change | Migration |
|--------|-----------|
| `Has64BitIndicator` → `Has64BitInstaller` | Update property references |
| Cache statistics property names | `CachedEntries` → `PackageCacheEntries` |
| New boolean for 64-bit detection | Now returns `$true`/`$false` from manifest, not heuristic guess |

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**Mark Ringo** - [RingoSystems](https://github.com/Ringosystems)

## Acknowledgments

- [winget.run](https://winget.run) for providing the REST API
- [Windows Package Manager](https://github.com/microsoft/winget-cli) team at Microsoft
- The PowerShell community for feedback and testing
