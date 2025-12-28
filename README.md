# WinGetLookup

[![PowerShell Gallery](https://img.shields.io/badge/PowerShell%20Gallery-v1.7.0-blue)](https://www.powershellgallery.com/packages/WinGetLookup)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/powershell/)

A PowerShell module to query the WinGet (Windows Package Manager) repository for package availability **without requiring WinGet to be installed locally**.

![WinGetLookup](icon.png)

## Features

- 🔍 **API-Based Lookups** - Query WinGet repository via REST API (no WinGet CLI required)
- 🎯 **Smart Matching** - Intelligent algorithm to find the best package match
- 📦 **64-bit Detection** - Check if 64-bit versions are available
- ⚡ **Session Caching** - Minimize API calls with automatic response caching
- 🏢 **Publisher Filtering** - Filter by publisher for precise matching
- 🔧 **Pipeline Support** - Full PowerShell pipeline integration

## Installation

### From PowerShell Gallery (Recommended)

```powershell
Install-Module -Name WinGetLookup -Scope CurrentUser
```

### Manual Installation

1. Clone this repository:
   ```powershell
   git clone https://github.com/Ringosystems/WinGetLookup.git
   ```

2. Copy the module to your PowerShell modules path:
   ```powershell
   Copy-Item -Path .\WinGetLookup -Destination "$env:USERPROFILE\Documents\PowerShell\Modules\" -Recurse
   ```

3. Import the module:
   ```powershell
   Import-Module WinGetLookup
   ```

## Requirements

- **PowerShell 5.1** (Windows PowerShell) or **PowerShell 7+** (PowerShell Core)
- Internet connectivity for API access
- No WinGet installation required for core functionality

### Supported Platforms

| Platform | Version |
|----------|---------|
| Windows 10 | 1709 (build 16299) or later |
| Windows 11 | All versions |
| Windows Server 2019 | Build 17763 or later |
| Windows Server 2022 | All versions |

## Quick Start

```powershell
# Import the module
Import-Module WinGetLookup

# Check if an application is available in WinGet
Test-WinGetPackage -DisplayName "7-Zip"
# Returns: 1 (available) or 0 (not found)

# Get detailed package information
Get-WinGetPackageInfo -DisplayName "Visual Studio Code"

# Check if 64-bit version is available
Test-WinGetPackage -DisplayName "Notepad++" -Require64Bit
```

## Functions

### Test-WinGetPackage

Tests if an application package exists in the WinGet repository.

```powershell
# Basic check
Test-WinGetPackage -DisplayName "VLC"

# With publisher filter
Test-WinGetPackage -DisplayName "PuTTY" -Publisher "Simon Tatham"

# With exact package ID
Test-WinGetPackage -DisplayName "Chrome" -PackageId "Google.Chrome"

# Require 64-bit version
Test-WinGetPackage -DisplayName "7-Zip" -Require64Bit

# Pipeline support
@("Notepad++", "7-Zip", "VLC") | ForEach-Object {
    [PSCustomObject]@{
        Name = $_
        Available = Test-WinGetPackage $_
    }
}
```

**Returns:** `1` if package is found, `0` if not found or error occurs.

### Get-WinGetPackageInfo

Retrieves detailed information about a WinGet package.

```powershell
# Get package details
$package = Get-WinGetPackageInfo -DisplayName "7-Zip"
$package | Format-List

# Select specific properties
Get-WinGetPackageInfo "Visual Studio Code" | Select-Object Id, Name, Publisher, Version
```

**Returns:** PSCustomObject with package details (Id, Name, Publisher, Version, Description, etc.) or `$null` if not found.

### Test-WinGet64BitAvailable

Checks if a 64-bit version of a package is available via WinGet CLI.

```powershell
# Check 64-bit availability (requires WinGet CLI)
Test-WinGet64BitAvailable -PackageId "Adobe.Acrobat.Reader.32-bit"
```

**Note:** This function requires WinGet CLI to be installed.

### Get-WinGet64BitPackageId

Gets the 64-bit package ID variant for a given package.

```powershell
# Convert 32-bit package ID to 64-bit variant
Get-WinGet64BitPackageId -PackageId "Adobe.Acrobat.Reader.32-bit"
# Returns: Adobe.Acrobat.Reader.64-bit
```

### Clear-WinGetCache

Clears the session-level package cache.

```powershell
# Clear all cached API responses
Clear-WinGetCache
```

### Get-WinGetCacheStatistics

Gets cache performance statistics.

```powershell
# View cache stats
Get-WinGetCacheStatistics

# Output:
# CacheEntries  : 5
# CacheHits     : 12
# CacheMisses   : 5
# HitRatio      : 70.59%
```

### Initialize-WinGetPackageCache

Pre-warms the cache with common package queries.

```powershell
# Pre-load cache for common packages
Initialize-WinGetPackageCache -PackageNames @("7-Zip", "Notepad++", "VLC", "Firefox")
```

## Use Cases

### Application Inventory Assessment

```powershell
# Check which installed apps are available in WinGet
$installedApps = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object { $_.DisplayName } |
    Select-Object DisplayName

$results = $installedApps | ForEach-Object {
    [PSCustomObject]@{
        Application = $_.DisplayName
        InWinGet = if (Test-WinGetPackage $_.DisplayName) { "Yes" } else { "No" }
    }
}

$results | Format-Table -AutoSize
```

### Pre-Installation Validation

```powershell
$appsToInstall = @("7-Zip", "Notepad++", "NonExistentApp")

foreach ($app in $appsToInstall) {
    if (Test-WinGetPackage $app) {
        Write-Host "✓ $app is available - ready to install" -ForegroundColor Green
    } else {
        Write-Host "✗ $app not found in WinGet" -ForegroundColor Red
    }
}
```

### 32-bit to 64-bit Migration

```powershell
# Find 32-bit apps and check for 64-bit alternatives
$32bitApps = Get-ItemProperty HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object { $_.DisplayName }

foreach ($app in $32bitApps) {
    $info = Get-WinGetPackageInfo -DisplayName $app.DisplayName
    if ($info) {
        $has64Bit = Test-WinGetPackage -DisplayName $app.DisplayName -Require64Bit
        Write-Host "$($app.DisplayName): 64-bit available = $has64Bit"
    }
}
```

## How It Works

WinGetLookup uses the [winget.run](https://winget.run) REST API to query the WinGet package repository. This approach offers several advantages:

1. **No Local WinGet Required** - Works on systems without WinGet installed
2. **Faster Queries** - API calls are faster than CLI operations
3. **Cross-Platform Potential** - API can be called from any platform
4. **Automation-Friendly** - No interactive prompts or UI elements

### Caching

To minimize API calls and improve performance, WinGetLookup implements session-level caching:

- API responses are cached in memory for the PowerShell session
- Subsequent queries for the same package use cached results
- Cache can be manually cleared with `Clear-WinGetCache`
- Cache statistics available via `Get-WinGetCacheStatistics`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**Mark Ringo** - [RingoSystems](https://github.com/Ringosystems)

## Acknowledgments

- [winget.run](https://winget.run) for providing the API
- [Windows Package Manager](https://github.com/microsoft/winget-cli) team at Microsoft
