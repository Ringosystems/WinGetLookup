#
# Module manifest for module 'WinGetLookup'
#
# Generated on: 12/26/2025
#

@{
    # Script module file associated with this manifest
    RootModule        = 'WinGetLookup.psm1'

    # Version number of this module
    ModuleVersion     = '1.7.1'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author            = 'Ringo'

    # Company or vendor of this module
    CompanyName       = 'RingoSystems Heavy Industuries'

    # Copyright statement for this module
    Copyright         = '(c) 2025 Mark Ringo. MIT License.'

    # Description of the functionality provided by this module
    Description       = 'A PowerShell module to query the WinGet (Windows Package Manager) repository for package availability. Uses the winget.run API to check if applications exist in the WinGet repository without requiring WinGet to be installed locally.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

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
        'Test-WinGetPackage',
        'Get-WinGetPackageInfo',
        'Clear-WinGetCache',
        'Get-WinGetCacheStatistics',
        'Test-WinGet64BitAvailable',
        'Get-WinGet64BitPackageId',
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
                'DevOps'
            )

            # A URL to the license for this module
            LicenseUri   = 'https://opensource.org/licenses/MIT'

            # A URL to the main website for this project
            ProjectUri   = 'https://github.com/Ringosystems/WinGetLookup'

            # A URL to an icon representing this module
            # Note: For PSGallery, this must be a publicly accessible HTTPS URL
            IconUri      = 'https://raw.githubusercontent.com/Ringosystems/WinGetLookup/master/icon.png'

            # ReleaseNotes of this module
            ReleaseNotes = @'
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

            # Prerelease string of this module
            Prerelease   = ''

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
