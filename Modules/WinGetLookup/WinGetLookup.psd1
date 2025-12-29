#
# Module manifest for module 'WinGetLookup'
#
# Generated on: 12/26/2025
#

@{
    # Script module file associated with this manifest
    RootModule        = 'WinGetLookup.psm1'

    # Version number of this module
    ModuleVersion     = '2.0.0'

    # Prerelease tag for alpha/beta releases
    # Note: Prerelease is specified in PSData section below

    # Supported PSEditions (PowerShell 7+ Core only)
    CompatiblePSEditions = @('Core')

    # ID used to uniquely identify this module
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author            = 'Ringo'

    # Company or vendor of this module
    CompanyName       = 'RingoSystems Heavy Industuries'

    # Copyright statement for this module
    Copyright         = '(c) 2025 Mark Ringo. MIT License.'

    # Description of the functionality provided by this module
    Description       = 'A PowerShell module to query the WinGet (Windows Package Manager) repository for package availability with high fidelity to WinGet''s internal operations. Uses the winget.run API to check package availability, retrieve actual installer metadata (architectures, installer types, scopes), compare versions, and correlate MSI ProductCodes - all without requiring WinGet to be installed locally.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @()

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module
    ScriptsToProcess  = @()

    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess    = @()

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess  = @()

    # Modules to import as nested modules of the module specified in RootModule
    NestedModules     = @()

    # Functions to export from this module
    FunctionsToExport = @(
        # Package lookup
        'Test-WinGetPackage',
        'Get-WinGetPackageInfo',
        
        # Version utilities
        'Compare-WinGetVersion',
        'Get-WinGetLatestVersion',
        
        # CLI-based operations
        'Test-WinGet64BitAvailable',
        'Get-WinGet64BitPackageId',
        'Find-WinGetPackageByProductCode',
        
        # Cache management
        'Clear-WinGetCache',
        'Get-WinGetCacheStatistics',
        'Initialize-WinGetPackageCache'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @()

    # DSC resources to export from this module
    DscResourcesToExport = @()

    # List of all modules packaged with this module
    ModuleList        = @()

    # List of all files packaged with this module
    FileList          = @(
        'WinGetLookup.psm1',
        'WinGetLookup.psd1',
        'icon.png',
        'LICENSE'
    )

    # Private data to pass to the module specified in RootModule
    PrivateData       = @{
        PSData = @{
            # Tags applied to this module for discoverability in online galleries
            Tags         = @(
                'WinGet',
                'WindowsPackageManager',
                'PackageManager',
                'PackageLookup',
                'Windows',
                'Automation',
                'DevOps',
                'Intune',
                'SCCM',
                'ConfigMgr',
                'AppDeployment'
            )

            # A URL to the license for this module
            LicenseUri   = 'https://opensource.org/licenses/MIT'

            # A URL to the main website for this project
            ProjectUri   = 'https://github.com/Ringosystems/WinGetLookup'

            # A URL to an icon representing this module
            # Note: For PSGallery, this must be a publicly accessible HTTPS URL
            IconUri      = 'https://raw.githubusercontent.com/Ringosystems/WinGetLookup/master/icon.png'

            # Prerelease tag (alpha, beta, rc, etc.) - leave empty for stable releases
            # Prerelease   = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
## Version 2.0.0 (December 28, 2025) - STABLE RELEASE
### Summary
Major release with true WinGet manifest fidelity, PowerShell 7.0+ only.

## Version 2.0.0-alpha3 (December 28, 2025)
### Breaking Change
- Now requires PowerShell 7.0+ (dropped Windows PowerShell 5.1 support)
- Simplified codebase by removing PS 5.1 compatibility code

## Version 2.0.0-alpha2 (December 28, 2025)
### Bug Fixes
- Fixed PowerShell 7+ JSON parsing issue with case-sensitive keys (API returned CreatedAt vs createdAt)
- Fixed primary word extraction bug where single-item arrays were incorrectly indexed as strings

## Version 2.0.0-alpha1 (December 28, 2025)
### Major Refactor for WinGet Schema Fidelity (ALPHA RELEASE)

**⚠️ ALPHA RELEASE** - This is a pre-release version for testing. APIs may change before final 2.0.0 release.

This release significantly improves accuracy by using actual WinGet manifest data instead of heuristics.

### New Features
- **True Architecture Detection**: Queries actual manifest `Installers` array for x86/x64/arm/arm64 data
- **InstallerType Exposure**: Returns installer types (msi, exe, msix, inno, nullsoft, portable, etc.)
- **Scope Detection**: Shows available installation scopes (user, machine)
- **Version Comparison**: New `Compare-WinGetVersion` and `Get-WinGetLatestVersion` functions
- **ProductCode Search**: New `Find-WinGetPackageByProductCode` for MSI correlation
- **API Retry Logic**: Exponential backoff for transient failures (429, 5xx errors)
- **Enhanced Caching**: Separate manifest cache, full parameter-aware cache keys

### Improvements
- API queries now use `preferContains` and `splitQuery` for better multi-word matching
- Publisher filter applied at API level (server-side) for efficiency
- Hybrid scoring uses API's SearchScore combined with client-side validation
- `Get-WinGetPackageInfo` returns rich installer metadata

### Breaking Changes
- `Has64BitIndicator` property renamed to `Has64BitInstaller` (now boolean from manifest data)
- Cache statistics now include `ManifestCacheEntries` count

### New Exported Functions
- `Compare-WinGetVersion` - Compare two WinGet-style version strings
- `Get-WinGetLatestVersion` - Get highest version from array
- `Find-WinGetPackageByProductCode` - Search by MSI ProductCode GUID

### Enhanced Output Properties (Get-WinGetPackageInfo)
- `Architectures` - Available architectures (x86, x64, arm, arm64)
- `InstallerTypes` - Available installer types (msi, exe, msix, etc.)
- `AvailableScopes` - Installation scopes (user, machine)
- `LatestVersion` - Computed latest version from Versions array
- `Has64BitInstaller` - Boolean from actual manifest data

## Version 1.8.0 (December 28, 2025)
### Bug Fixes
- Fixed smart matching algorithm to prevent false positives
- Packages must now contain the primary search word to be considered a match
- Added minimum score threshold to filter out low-quality matches
- Example: "TeamViewer 15" no longer incorrectly matches "115Chrome"

### Improvements  
- Improved scoring for exact name matches
- Better handling of search terms with version numbers
- More accurate matching for common software names

## Version 1.7.1 (December 28, 2025)
### Updates
- Added MIT License file to module package
- Added module icon for PSGallery display
- Added comprehensive README documentation
- Published to GitHub: https://github.com/Ringosystems/WinGetLookup
- Updated ProjectUri and IconUri for PSGallery

## Version 1.7.0 (December 27, 2025)
### New Features
- Added Initialize-WinGetPackageCache function for cache pre-warming
- Performance improvements for batch operations

## Version 1.6.0 (December 26, 2025)
### New Features
- Added Get-WinGet64BitPackageId function to handle separate 64-bit packages
- Automatically detects when 32-bit and 64-bit versions are separate packages
- Converts package IDs like Adobe.Acrobat.Reader.32-bit to .64-bit variants
- Handles multiple naming patterns: .32-bit/.64-bit, -32-bit/-64-bit, .x86/.x64
- Returns correct package ID for installation (same package or 64-bit variant)

## Version 1.5.0 (December 26, 2025)
### New Features
- Added Test-WinGet64BitAvailable function for CLI-based 64-bit verification
- Uses local WinGet CLI (winget show --architecture x64) for definitive results
- More accurate than heuristic detection for packages without 64-bit metadata
- Supports packages like WinRAR that have x64 installers but no 64-bit indicators
- Includes timeout handling and proper process management

## Version 1.4.0 (December 26, 2025)
### New Features
- Get-WinGetPackageInfo now includes Has64BitIndicator property in output
- Has64BitIndicator indicates if the package appears to have a 64-bit version
- Based on package ID, name, and tags analysis (no additional API calls)
- Useful for determining if an upgrade from 32-bit to 64-bit is available

## Version 1.3.0 (December 26, 2025)
### New Features
- Added session-level caching to minimize redundant API calls
- New Clear-WinGetCache function to reset the cache
- New Get-WinGetCacheStatistics function to view cache performance
- Cache tracks hits, misses, and efficiency percentage
- Significantly improves performance when querying multiple similar applications

## Version 1.2.0 (December 26, 2025)
### New Features
- Added smart matching algorithm for better package selection from API results
- Added -Publisher parameter to filter results by publisher name
- Added -PackageId parameter for exact package ID matching
- Now fetches multiple results (10) from API and scores them to find best match
- Scoring considers: exact ID match, publisher match, name similarity, and ID patterns
- This resolves edge cases like "PuTTY" incorrectly returning "MTPuTTY"

## Version 1.1.0 (December 26, 2025)
### New Features
- Added -Require64Bit switch parameter to Test-WinGetPackage
- When specified, returns 1 only if a 64-bit version of the package is available
- Added helper functions for 64-bit detection based on package ID, name, and tags

## Version 1.0.0 (December 26, 2025)
### Initial Release
- Added Test-WinGetPackage function to check if a package exists in WinGet
- Added Get-WinGetPackageInfo function to retrieve detailed package information
- Uses winget.run API for package lookups (no local WinGet installation required)
- Full pipeline support for batch operations
- Comprehensive comment-based help documentation
'@

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            RequireLicenseAcceptance = $false

            # External module dependencies
            ExternalModuleDependencies = @()
        }
    }

    # HelpInfo URI of this module
    HelpInfoURI       = ''

    # Default prefix for commands exported from this module
    DefaultCommandPrefix = ''
}
