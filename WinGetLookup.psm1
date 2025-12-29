#Requires -Version 5.1

<#
.SYNOPSIS
    WinGetLookup PowerShell Module - Query WinGet package availability with high fidelity.

.DESCRIPTION
    This module provides functions to query the WinGet (Windows Package Manager) repository
    to determine if packages exist. It uses the winget.run API for package lookups.
    
    Features:
    - API-based lookups with actual manifest data (not heuristics)
    - True architecture detection from installer metadata (x86, x64, arm, arm64)
    - InstallerType awareness (msi, exe, msix, inno, nullsoft, portable, etc.)
    - Scope detection (user vs machine installation)
    - Smart matching algorithm using API SearchScore + client-side validation
    - Version comparison utilities following WinGet's comparison logic
    - Publisher filtering at API level for efficiency
    - Session-level caching with full parameter awareness
    - Retry logic with exponential backoff for API resilience
    - ProductCode/UpgradeCode correlation for MSI packages
    - Pipeline support throughout
    
    SUPPORTED PLATFORMS:
    - Windows 10 version 1709 (build 16299) or later
    - Windows 11 (all versions)
    - Windows Server 2019 (build 17763) or later
    - Windows Server 2022 (all versions)
    - PowerShell 5.1 (Windows PowerShell) and PowerShell 7+ (PowerShell Core)
    
    Note: The module's API-based functions work on any platform with internet access.
    The WinGet CLI-based functions require WinGet to be installed locally.

.NOTES
    Module Name: WinGetLookup
    Author: Mark Ringo
    Company: RingoSystems
    Version: 2.0.0-alpha1
    Date: December 28, 2025
    License: MIT
    Repository: https://github.com/Ringosystems/WinGetLookup
    
    ⚠️ ALPHA RELEASE - APIs may change before final 2.0.0 release.
    
    VERSION HISTORY:
    2.0.0-alpha1 - Major refactor for WinGet schema fidelity (ALPHA):
            - True architecture detection from manifest Installers array
            - InstallerType and Scope exposure in package info
            - Version comparison utilities (Compare-WinGetVersion, Get-WinGetLatestVersion)
            - API query optimization (preferContains, splitQuery, server-side publisher filter)
            - Cache key includes all query parameters
            - Retry logic with exponential backoff
            - ProductCode search function for MSI correlation
            - Hybrid scoring using API SearchScore + validation
    1.8.0 - Fixed smart matching to prevent false positives
    1.7.1 - Added MIT License, icon, README, published to GitHub.
    1.7.0 - Added Initialize-WinGetPackageCache for cache pre-warming.
    1.6.0 - Added Get-WinGet64BitPackageId for 32-bit to 64-bit package conversion.
    1.5.0 - Added Test-WinGet64BitAvailable for CLI-based x64 verification.
    1.4.0 - Added Has64BitIndicator property to package info output.
    1.3.0 - Added session-level caching with Clear-WinGetCache and Get-WinGetCacheStatistics.
    1.2.0 - Added smart matching algorithm with publisher filtering.
    1.1.0 - Added PackageId parameter for exact matching.
    1.0.0 - Initial release with Test-WinGetPackage and Get-WinGetPackageInfo.
#>

#region Private Variables
$Script:WinGetApiBaseUrl = 'https://api.winget.run/v2'
$Script:DefaultTimeout = 30
$Script:DefaultTakeCount = 10
$Script:MaxRetries = 3
$Script:BaseRetryDelayMs = 500

# Session-level cache for API responses
# Key format: "searchterm|pub:publisher|id:packageid" (all lowercase)
$Script:PackageCache = @{}
$Script:ManifestCache = @{}  # Separate cache for full manifest lookups
$Script:CacheHits = 0
$Script:CacheMisses = 0

# WinGet CLI path - cached at module load
$Script:WinGetCliPath = $null
$Script:WinGetCliAvailable = $false

# Valid WinGet architecture values (per schema v1.12)
$Script:ValidArchitectures = @('x86', 'x64', 'arm', 'arm64', 'neutral')

# Valid WinGet installer types (per schema v1.12)
$Script:ValidInstallerTypes = @(
    'msix', 'msi', 'appx', 'exe', 'zip', 'inno', 'nullsoft', 
    'wix', 'burn', 'pwa', 'portable', 'font'
)

# Valid scope values
$Script:ValidScopes = @('user', 'machine')
#endregion

#region Module Initialization
function Initialize-WinGetCliPath {
    <#
    .SYNOPSIS
        Finds and caches the WinGet CLI path once at module load.
    #>
    
    # Check standard PATH first
    $wingetCmd = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        $Script:WinGetCliPath = $wingetCmd.Source
        $Script:WinGetCliAvailable = $true
        return
    }
    
    # Check common locations
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    )
    
    foreach ($pathPattern in $possiblePaths) {
        $resolved = Get-Item -Path $pathPattern -ErrorAction SilentlyContinue | 
            Sort-Object -Property LastWriteTime -Descending | 
            Select-Object -First 1
        if ($resolved) {
            $Script:WinGetCliPath = $resolved.FullName
            $Script:WinGetCliAvailable = $true
            return
        }
    }
    
    # Try user profiles for SYSTEM context
    $userProfiles = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue
    foreach ($profile in $userProfiles) {
        $userWinget = Join-Path -Path $profile.FullName -ChildPath 'AppData\Local\Microsoft\WindowsApps\winget.exe'
        if (Test-Path -Path $userWinget) {
            $Script:WinGetCliPath = $userWinget
            $Script:WinGetCliAvailable = $true
            return
        }
    }
    
    $Script:WinGetCliAvailable = $false
}

# Initialize at module load
Initialize-WinGetCliPath
#endregion

#region Private Functions - API & Network

function Invoke-WinGetApiWithRetry {
    <#
    .SYNOPSIS
        Invokes a WinGet API call with retry logic and exponential backoff.
    .DESCRIPTION
        Handles transient failures (429 rate limit, 5xx server errors) with
        automatic retry using exponential backoff.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Uri,
        
        [int]$TimeoutSeconds = $Script:DefaultTimeout,
        
        [int]$MaxRetries = $Script:MaxRetries,
        
        [int]$BaseDelayMs = $Script:BaseRetryDelayMs
    )
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -lt $MaxRetries) {
        $attempt++
        
        try {
            $requestParams = @{
                Uri             = $Uri
                Method          = 'Get'
                TimeoutSec      = $TimeoutSeconds
                ErrorAction     = 'Stop'
                UseBasicParsing = $true
            }
            
            $response = Invoke-RestMethod @requestParams
            return $response
        }
        catch {
            $lastError = $_
            $statusCode = $null
            
            # Try to extract HTTP status code
            if ($_.Exception.Response) {
                try {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
                catch {
                    # Some PowerShell versions handle this differently
                    if ($_.Exception.Response.StatusCode) {
                        $statusCode = $_.Exception.Response.StatusCode.value__
                    }
                }
            }
            
            # Determine if we should retry
            $retryableStatusCodes = @(429, 500, 502, 503, 504)
            $isRetryable = ($statusCode -and $statusCode -in $retryableStatusCodes) -or 
                           ($_.Exception -is [System.Net.WebException] -and 
                            $_.Exception.Status -in @('Timeout', 'ConnectFailure', 'ReceiveFailure'))
            
            if ($isRetryable -and $attempt -lt $MaxRetries) {
                $delay = $BaseDelayMs * [Math]::Pow(2, $attempt - 1)
                Write-Verbose "API request failed (attempt $attempt/$MaxRetries), retrying in $delay ms. Status: $statusCode"
                Start-Sleep -Milliseconds $delay
                continue
            }
            
            # Not retryable or max retries exceeded
            throw
        }
    }
    
    # Should not reach here, but just in case
    throw $lastError
}

function Get-CacheKey {
    <#
    .SYNOPSIS
        Generates a consistent cache key from search parameters.
    .DESCRIPTION
        Includes all query parameters in the cache key to prevent
        returning stale filtered results.
    #>
    param(
        [string]$SearchTerm,
        [string]$Publisher,
        [string]$PackageId
    )
    
    $termPart = if ($SearchTerm) { $SearchTerm.ToLowerInvariant().Trim() } else { '' }
    $pubPart = if ($Publisher) { $Publisher.ToLowerInvariant().Trim() } else { '' }
    $idPart = if ($PackageId) { $PackageId.ToLowerInvariant().Trim() } else { '' }
    
    return "$termPart|pub:$pubPart|id:$idPart"
}

function Get-CachedApiResponse {
    <#
    .SYNOPSIS
        Retrieves cached API response or makes a new API call with caching.
    .DESCRIPTION
        Implements session-level caching with full parameter awareness.
        Uses optimized API query parameters for better results.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SearchTerm,
        
        [string]$Publisher,
        
        [string]$PackageId,
        
        [int]$TimeoutSeconds = $Script:DefaultTimeout
    )
    
    # Generate cache key including all parameters
    $cacheKey = Get-CacheKey -SearchTerm $SearchTerm -Publisher $Publisher -PackageId $PackageId
    
    # Check cache
    if ($Script:PackageCache.ContainsKey($cacheKey)) {
        $Script:CacheHits++
        Write-Verbose "Cache HIT for key '$cacheKey' (Total hits: $($Script:CacheHits))"
        return $Script:PackageCache[$cacheKey]
    }
    
    # Cache miss
    $Script:CacheMisses++
    Write-Verbose "Cache MISS for key '$cacheKey' - calling API (Total misses: $($Script:CacheMisses))"
    
    try {
        # Build optimized query parameters
        $queryParams = [System.Collections.ArrayList]@()
        
        # Primary search term
        $encodedName = [System.Uri]::EscapeDataString($SearchTerm)
        [void]$queryParams.Add("name=$encodedName")
        
        # Server-side publisher filter (more efficient than client-side)
        if ($Publisher) {
            $encodedPublisher = [System.Uri]::EscapeDataString($Publisher)
            [void]$queryParams.Add("publisher=$encodedPublisher")
        }
        
        # Optimized search parameters
        [void]$queryParams.Add("ensureContains=true")   # Require term in results
        [void]$queryParams.Add("preferContains=true")   # Let API rank by match quality
        [void]$queryParams.Add("splitQuery=true")       # Handle multi-word names
        [void]$queryParams.Add("take=$($Script:DefaultTakeCount)")
        
        $apiUrl = "$Script:WinGetApiBaseUrl/packages?" + ($queryParams -join '&')
        Write-Verbose "API URL: $apiUrl"
        
        # Make request with retry logic
        $response = Invoke-WinGetApiWithRetry -Uri $apiUrl -TimeoutSeconds $TimeoutSeconds
        
        # Parse response
        $packages = $null
        
        if ($response -is [string]) {
            $parsed = $response | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($parsed -and $parsed.Packages) {
                $packages = $parsed.Packages
            }
        }
        elseif ($response.Packages) {
            $packages = $response.Packages
        }
        
        # Ensure we have an array
        if ($null -eq $packages) {
            $packages = @()
        }
        elseif ($packages -isnot [array]) {
            $packages = @($packages)
        }
        
        # Cache the result
        $Script:PackageCache[$cacheKey] = $packages
        
        return $packages
    }
    catch {
        Write-Verbose "API error for '$SearchTerm': $($_.Exception.Message)"
        # Cache empty result to avoid repeated failed calls
        $Script:PackageCache[$cacheKey] = @()
        return @()
    }
}

function Get-PackageManifestDetails {
    <#
    .SYNOPSIS
        Fetches full manifest details for a specific package.
    .DESCRIPTION
        Retrieves the complete package data including Installers array
        with Architecture, InstallerType, and Scope information.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,
        
        [int]$TimeoutSeconds = $Script:DefaultTimeout
    )
    
    # Check manifest cache
    $cacheKey = $PackageId.ToLowerInvariant()
    if ($Script:ManifestCache.ContainsKey($cacheKey)) {
        Write-Verbose "Manifest cache HIT for '$PackageId'"
        return $Script:ManifestCache[$cacheKey]
    }
    
    Write-Verbose "Fetching full manifest for: $PackageId"
    
    try {
        # Parse package ID into Publisher and Package parts
        # Format is typically: Publisher.PackageName or Publisher.Sub.PackageName
        $parts = $PackageId -split '\.', 2
        
        if ($parts.Count -lt 2) {
            Write-Verbose "Invalid package ID format: $PackageId"
            return $null
        }
        
        $publisher = $parts[0]
        $package = $parts[1]
        
        # URL encode the parts
        $encodedPublisher = [System.Uri]::EscapeDataString($publisher)
        $encodedPackage = [System.Uri]::EscapeDataString($package)
        
        $manifestUrl = "$Script:WinGetApiBaseUrl/packages/$encodedPublisher/$encodedPackage"
        Write-Verbose "Manifest URL: $manifestUrl"
        
        $response = Invoke-WinGetApiWithRetry -Uri $manifestUrl -TimeoutSeconds $TimeoutSeconds
        
        # Cache and return
        $Script:ManifestCache[$cacheKey] = $response
        return $response
    }
    catch {
        Write-Verbose "Failed to fetch manifest for $PackageId : $($_.Exception.Message)"
        $Script:ManifestCache[$cacheKey] = $null
        return $null
    }
}

function Invoke-WinGetCliCommand {
    <#
    .SYNOPSIS
        Executes a WinGet CLI command with timeout and proper output handling.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        
        [int]$TimeoutSeconds = 30
    )
    
    if (-not $Script:WinGetCliAvailable) {
        return @{
            Success  = $false
            ExitCode = -1
            StdOut   = ''
            StdErr   = 'WinGet CLI not available'
        }
    }
    
    $process = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Script:WinGetCliPath
        $psi.Arguments = $Arguments -join ' '
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        
        [void]$process.Start()
        
        # Read output asynchronously
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        
        # Wait with timeout
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            return @{
                Success  = $false
                ExitCode = -1
                StdOut   = ''
                StdErr   = "Command timed out after $TimeoutSeconds seconds"
            }
        }
        
        return @{
            Success  = ($process.ExitCode -eq 0)
            ExitCode = $process.ExitCode
            StdOut   = $stdoutTask.Result
            StdErr   = $stderrTask.Result
        }
    }
    catch {
        return @{
            Success  = $false
            ExitCode = -1
            StdOut   = ''
            StdErr   = $_.Exception.Message
        }
    }
    finally {
        if ($process) {
            $process.Dispose()
        }
    }
}
#endregion

#region Private Functions - Matching & Parsing

function Get-BestPackageMatch {
    <#
    .SYNOPSIS
        Selects the best matching package using hybrid API + client scoring.
    .DESCRIPTION
        Uses API's SearchScore as primary ranking, then applies client-side
        validation to ensure relevance. Requires packages to contain the
        primary search word to prevent false positives.
    #>
    param(
        [array]$Packages,
        [string]$SearchTerm,
        [string]$Publisher,
        [string]$PackageId
    )
    
    if (-not $Packages -or $Packages.Count -eq 0) {
        return $null
    }
    
    # Exact PackageId match takes absolute priority
    if ($PackageId) {
        $exactMatch = $Packages | Where-Object { $_.Id -eq $PackageId } | Select-Object -First 1
        if ($exactMatch) {
            Write-Verbose "Exact PackageId match found: $PackageId"
            return $exactMatch
        }
        Write-Verbose "PackageId '$PackageId' not found in results"
        return $null
    }
    
    $searchTermLower = $SearchTerm.ToLower()
    $publisherLower = if ($Publisher) { $Publisher.ToLower() } else { $null }
    
    # Extract primary word (filter out pure version numbers)
    $searchWords = $searchTermLower -split '\s+' | Where-Object { 
        $_ -notmatch '^\d+(\.\d+)+$' -and $_.Length -gt 0
    }
    $primaryWord = if ($searchWords.Count -gt 0) { $searchWords[0] } else { $searchTermLower }
    
    Write-Verbose "Primary search word: '$primaryWord'"
    
    # First pass: filter to only packages containing primary word
    $validPackages = @()
    
    foreach ($pkg in $Packages) {
        $pkgId = $pkg.Id
        $pkgName = if ($pkg.Latest) { $pkg.Latest.Name } else { $pkg.Name }
        $pkgPublisher = if ($pkg.Latest) { $pkg.Latest.Publisher } else { $pkg.Publisher }
        
        $pkgIdLower = if ($pkgId) { $pkgId.ToLower() } else { '' }
        $pkgNameLower = if ($pkgName) { $pkgName.ToLower() } else { '' }
        $pkgPublisherLower = if ($pkgPublisher) { $pkgPublisher.ToLower() } else { '' }
        
        # Must contain primary word somewhere
        $hasPrimaryWord = ($pkgIdLower -like "*$primaryWord*") -or 
                          ($pkgNameLower -like "*$primaryWord*") -or
                          ($pkgPublisherLower -like "*$primaryWord*")
        
        if (-not $hasPrimaryWord) {
            continue
        }
        
        # Publisher filter validation (if specified and not already filtered by API)
        if ($publisherLower) {
            $publisherMatch = ($pkgPublisherLower -eq $publisherLower) -or 
                              ($pkgPublisherLower -like "*$publisherLower*")
            if (-not $publisherMatch) {
                continue
            }
        }
        
        $validPackages += $pkg
    }
    
    if ($validPackages.Count -eq 0) {
        Write-Verbose "No packages passed validation filters"
        return $null
    }
    
    # Second pass: score and rank
    $scoredPackages = @()
    
    foreach ($pkg in $validPackages) {
        $score = 0
        $pkgId = $pkg.Id
        $pkgName = if ($pkg.Latest) { $pkg.Latest.Name } else { $pkg.Name }
        $pkgPublisher = if ($pkg.Latest) { $pkg.Latest.Publisher } else { $pkg.Publisher }
        
        $pkgIdLower = if ($pkgId) { $pkgId.ToLower() } else { '' }
        $pkgNameLower = if ($pkgName) { $pkgName.ToLower() } else { '' }
        $pkgPublisherLower = if ($pkgPublisher) { $pkgPublisher.ToLower() } else { '' }
        
        # Use API's SearchScore if available (0-100 scale typically)
        if ($pkg.SearchScore) {
            $score += [int]($pkg.SearchScore * 0.5)  # Weight API score at 50%
        }
        
        # Base score for passing validation
        $score += 10
        
        # +100: Package ID = SearchTerm.SearchTerm pattern
        $expectedId = "$searchTermLower.$searchTermLower"
        if ($pkgIdLower -eq $expectedId) {
            $score += 100
        }
        
        # +75: Exact publisher match
        if ($publisherLower -and $pkgPublisherLower -eq $publisherLower) {
            $score += 75
        }
        
        # +50: Exact name match
        if ($pkgNameLower -eq $searchTermLower) {
            $score += 50
        }
        
        # +30: Name equals primary word
        if ($pkgNameLower -eq $primaryWord) {
            $score += 30
        }
        
        # +25: Name starts with search term
        if ($pkgNameLower.StartsWith($searchTermLower)) {
            $score += 25
        }
        
        # +20: Name starts with primary word
        if ($pkgNameLower.StartsWith($primaryWord)) {
            $score += 20
        }
        
        # +15: Package ID starts with search term
        if ($pkgIdLower.StartsWith($searchTermLower)) {
            $score += 15
        }
        
        # +10: Package ID contains search term in standard pattern
        if ($pkgIdLower -like "*.$searchTermLower" -or $pkgIdLower -like "$searchTermLower.*") {
            $score += 10
        }
        
        $scoredPackages += [PSCustomObject]@{
            Package = $pkg
            Score   = $score
            Id      = $pkgId
            Name    = $pkgName
        }
    }
    
    # Require minimum score
    $minScore = 15
    $best = $scoredPackages | 
            Where-Object { $_.Score -ge $minScore } | 
            Sort-Object -Property Score -Descending | 
            Select-Object -First 1
    
    if ($best) {
        Write-Verbose "Best match: $($best.Name) ($($best.Id)) with score $($best.Score)"
        return $best.Package
    }
    
    return $null
}

function Get-InstallerMetadata {
    <#
    .SYNOPSIS
        Extracts installer metadata (architectures, types, scopes) from package data.
    .DESCRIPTION
        Parses the Installers array from package manifest to extract
        all available architectures, installer types, and scopes.
    #>
    param(
        [Parameter(Mandatory)]
        $Package
    )
    
    $result = @{
        Architectures  = @()
        InstallerTypes = @()
        Scopes         = @()
        Has64Bit       = $false
        HasArm64       = $false
        Installers     = @()
    }
    
    # Try to get installers from Latest property
    $installers = $null
    if ($Package.Latest -and $Package.Latest.Installers) {
        $installers = $Package.Latest.Installers
    }
    elseif ($Package.Installers) {
        $installers = $Package.Installers
    }
    
    if (-not $installers -or $installers.Count -eq 0) {
        Write-Verbose "No installer metadata found in package"
        return $result
    }
    
    $result.Installers = $installers
    
    foreach ($installer in $installers) {
        # Architecture
        if ($installer.Architecture) {
            $arch = $installer.Architecture.ToLower()
            if ($arch -notin $result.Architectures) {
                $result.Architectures += $arch
            }
            if ($arch -eq 'x64') {
                $result.Has64Bit = $true
            }
            if ($arch -eq 'arm64') {
                $result.HasArm64 = $true
            }
        }
        
        # Installer Type
        if ($installer.InstallerType) {
            $type = $installer.InstallerType.ToLower()
            if ($type -notin $result.InstallerTypes) {
                $result.InstallerTypes += $type
            }
        }
        
        # Scope
        if ($installer.Scope) {
            $scope = $installer.Scope.ToLower()
            if ($scope -notin $result.Scopes) {
                $result.Scopes += $scope
            }
        }
    }
    
    # Default scope if none specified
    if ($result.Scopes.Count -eq 0) {
        $result.Scopes = @('machine')
    }
    
    return $result
}

function Test-64BitFromManifest {
    <#
    .SYNOPSIS
        Checks for x64/arm64 architecture using actual manifest data.
    .DESCRIPTION
        Queries the package manifest to check for 64-bit installer availability.
        This is authoritative, not heuristic-based.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,
        
        [int]$TimeoutSeconds = 15
    )
    
    # First try to get from cached search results
    foreach ($cacheEntry in $Script:PackageCache.Values) {
        if ($cacheEntry -is [array]) {
            $pkg = $cacheEntry | Where-Object { $_.Id -eq $PackageId } | Select-Object -First 1
            if ($pkg) {
                $metadata = Get-InstallerMetadata -Package $pkg
                if ($metadata.Has64Bit -or $metadata.HasArm64) {
                    return $true
                }
            }
        }
    }
    
    # Fetch full manifest if not in cache
    $manifest = Get-PackageManifestDetails -PackageId $PackageId -TimeoutSeconds $TimeoutSeconds
    
    if ($manifest) {
        $metadata = Get-InstallerMetadata -Package $manifest
        return ($metadata.Has64Bit -or $metadata.HasArm64)
    }
    
    return $false
}
#endregion

#region Public Functions - Version Comparison

function Compare-WinGetVersion {
    <#
    .SYNOPSIS
        Compares two WinGet-style version strings.

    .DESCRIPTION
        Compares version strings following WinGet's version comparison logic.
        Versions are split on dots and compared segment-by-segment.
        Numeric segments are compared numerically; string segments use
        ordinal comparison.
        
        WinGet supports various version formats:
        - Standard: 1.0, 1.0.0, 1.0.0.0
        - Date-based: 2024.01.15
        - Mixed: 24.09, 1.0-beta

    .PARAMETER Version1
        The first version string to compare.

    .PARAMETER Version2
        The second version string to compare.

    .OUTPUTS
        System.Int32
        Returns -1 if Version1 < Version2
        Returns  0 if Version1 = Version2
        Returns  1 if Version1 > Version2

    .EXAMPLE
        Compare-WinGetVersion -Version1 "1.0.0" -Version2 "1.0.1"
        Returns -1 (Version1 is older)

    .EXAMPLE
        Compare-WinGetVersion -Version1 "2.0" -Version2 "1.9.9"
        Returns 1 (Version1 is newer)

    .EXAMPLE
        Compare-WinGetVersion "24.09" "24.10"
        Returns -1 (Version1 is older)

    .NOTES
        Author: Mark Ringo
        Version: 2.0.0
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Version1,
        
        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Version2
    )
    
    # Normalize: remove common prefixes
    $v1Clean = $Version1 -replace '^[vV]', ''
    $v2Clean = $Version2 -replace '^[vV]', ''
    
    # Split on dots
    $v1Parts = $v1Clean -split '\.'
    $v2Parts = $v2Clean -split '\.'
    
    $maxLength = [Math]::Max($v1Parts.Count, $v2Parts.Count)
    
    for ($i = 0; $i -lt $maxLength; $i++) {
        $p1 = if ($i -lt $v1Parts.Count) { $v1Parts[$i] } else { '0' }
        $p2 = if ($i -lt $v2Parts.Count) { $v2Parts[$i] } else { '0' }
        
        # Try numeric comparison first
        $num1 = 0
        $num2 = 0
        $isNum1 = [int]::TryParse($p1, [ref]$num1)
        $isNum2 = [int]::TryParse($p2, [ref]$num2)
        
        if ($isNum1 -and $isNum2) {
            # Both are numeric
            if ($num1 -lt $num2) { return -1 }
            if ($num1 -gt $num2) { return 1 }
        }
        else {
            # String comparison (handles mixed like "1.0-beta")
            $cmp = [string]::Compare($p1, $p2, [StringComparison]::OrdinalIgnoreCase)
            if ($cmp -ne 0) { return $cmp }
        }
    }
    
    return 0
}

function Get-WinGetLatestVersion {
    <#
    .SYNOPSIS
        Returns the latest version from a list of WinGet version strings.

    .DESCRIPTION
        Sorts version strings using WinGet's comparison logic and returns
        the highest (latest) version.

    .PARAMETER Versions
        Array of version strings to evaluate.

    .OUTPUTS
        System.String
        The latest (highest) version string, or $null if input is empty.

    .EXAMPLE
        Get-WinGetLatestVersion -Versions @("1.0", "2.0", "1.5")
        Returns "2.0"

    .EXAMPLE
        @("24.09", "24.10", "24.08") | Get-WinGetLatestVersion
        Returns "24.10"

    .NOTES
        Author: Mark Ringo
        Version: 2.0.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [string[]]$Versions
    )
    
    begin {
        $allVersions = @()
    }
    
    process {
        $allVersions += $Versions
    }
    
    end {
        if ($allVersions.Count -eq 0) {
            return $null
        }
        
        if ($allVersions.Count -eq 1) {
            return $allVersions[0]
        }
        
        # Sort using our comparison function
        $sorted = $allVersions | Sort-Object -Property @{
            Expression = {
                # Create a sortable key
                $parts = ($_ -replace '^[vV]', '') -split '\.'
                $key = ''
                foreach ($part in $parts) {
                    $num = 0
                    if ([int]::TryParse($part, [ref]$num)) {
                        $key += $num.ToString('D10')
                    }
                    else {
                        $key += $part.PadRight(10)
                    }
                }
                $key
            }
        } -Descending
        
        return $sorted | Select-Object -First 1
    }
}
#endregion

#region Public Functions - Package Lookup

function Test-WinGetPackage {
    <#
    .SYNOPSIS
        Tests if an application package exists in the WinGet repository.

    .DESCRIPTION
        Queries the winget.run API to determine if a package with the specified 
        display name exists in the Windows Package Manager (WinGet) repository.
        
        Uses smart matching with API-level and client-side filtering.
        Can verify 64-bit availability using actual manifest architecture data.

    .PARAMETER DisplayName
        The display name of the application to search for.

    .PARAMETER Publisher
        Optional publisher name to filter results (applied at API level).

    .PARAMETER PackageId
        Optional exact WinGet package ID for direct matching.

    .PARAMETER Require64Bit
        When specified, returns 1 only if an x64 or arm64 installer is available.
        Uses actual manifest data, not heuristics.

    .PARAMETER TimeoutSeconds
        The timeout in seconds for the API request. Default is 30.

    .OUTPUTS
        System.Int32
        Returns 1 if the package is found (and meets requirements).
        Returns 0 if not found or requirements not met.

    .EXAMPLE
        Test-WinGetPackage -DisplayName "Visual Studio Code"
        Returns 1 if found.

    .EXAMPLE
        Test-WinGetPackage -DisplayName "7-Zip" -Require64Bit
        Returns 1 only if 7-Zip has an x64 installer.

    .EXAMPLE
        Test-WinGetPackage -DisplayName "PuTTY" -Publisher "Simon Tatham"
        Returns 1 only if PuTTY by Simon Tatham is found.

    .NOTES
        Author: Mark Ringo
        Version: 2.0.0
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Name', 'ApplicationName', 'AppName')]
        [string]$DisplayName,

        [Parameter()]
        [Alias('Vendor', 'Author')]
        [string]$Publisher,

        [Parameter()]
        [Alias('Id', 'WinGetId')]
        [string]$PackageId,

        [Parameter()]
        [switch]$Require64Bit,

        [Parameter()]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = $Script:DefaultTimeout
    )

    begin {
        Write-Verbose "Starting WinGet package lookup..."
    }

    process {
        Write-Verbose "Searching for package: $DisplayName"
        
        try {
            # Get packages with all filters
            $packages = Get-CachedApiResponse -SearchTerm $DisplayName -Publisher $Publisher -PackageId $PackageId -TimeoutSeconds $TimeoutSeconds
            
            if (-not $packages -or $packages.Count -eq 0) {
                Write-Verbose "No packages found for: $DisplayName"
                return 0
            }
            
            # Find best match
            $bestMatch = Get-BestPackageMatch -Packages $packages -SearchTerm $DisplayName -Publisher $Publisher -PackageId $PackageId
            
            if (-not $bestMatch) {
                Write-Verbose "No matching package found for: $DisplayName"
                return 0
            }
            
            $matchedId = $bestMatch.Id
            $matchedName = if ($bestMatch.Latest) { $bestMatch.Latest.Name } else { $bestMatch.Name }
            Write-Verbose "Best match: $matchedName ($matchedId)"
            
            # Check 64-bit requirement using manifest data
            if ($Require64Bit) {
                $metadata = Get-InstallerMetadata -Package $bestMatch
                
                if ($metadata.Has64Bit -or $metadata.HasArm64) {
                    Write-Verbose "64-bit installer available for: $matchedName (Architectures: $($metadata.Architectures -join ', '))"
                    return 1
                }
                
                # Fallback: fetch full manifest if installer data not in search results
                $has64Bit = Test-64BitFromManifest -PackageId $matchedId -TimeoutSeconds $TimeoutSeconds
                if ($has64Bit) {
                    Write-Verbose "64-bit installer confirmed via manifest for: $matchedName"
                    return 1
                }
                
                Write-Verbose "No 64-bit installer found for: $matchedName"
                return 0
            }
            
            return 1
        }
        catch {
            Write-Verbose "Error searching for $DisplayName : $($_.Exception.Message)"
            Write-Warning "Error querying WinGet API: $($_.Exception.Message)"
            return 0
        }
    }

    end {
        Write-Verbose "Package lookup completed."
    }
}

function Get-WinGetPackageInfo {
    <#
    .SYNOPSIS
        Retrieves detailed information about a WinGet package.

    .DESCRIPTION
        Queries the winget.run API to retrieve comprehensive package information
        including ID, publisher, versions, and installer metadata.
        
        Returns actual architecture, installer type, and scope data from
        the package manifest - not heuristic-based guesses.

    .PARAMETER DisplayName
        The display name of the application to search for.

    .PARAMETER Publisher
        Optional publisher name to filter results.

    .PARAMETER PackageId
        Optional exact WinGet package ID for direct matching.

    .PARAMETER TimeoutSeconds
        The timeout in seconds for the API request. Default is 30.

    .OUTPUTS
        PSCustomObject with properties:
        - Id: WinGet package identifier
        - Name: Display name
        - Publisher: Publisher name
        - Description: Package description
        - Homepage: Publisher/product URL
        - License: License type
        - Tags: Comma-separated tags
        - Versions: Available versions
        - LatestVersion: The latest available version
        - Architectures: Available architectures (x86, x64, arm, arm64)
        - InstallerTypes: Available installer types (msi, exe, msix, etc.)
        - AvailableScopes: Installation scopes (user, machine)
        - Has64BitInstaller: Boolean indicating x64/arm64 availability
        - Found: Boolean indicating if package was found

    .EXAMPLE
        Get-WinGetPackageInfo -DisplayName "7-Zip"
        Returns full package details including architecture info.

    .EXAMPLE
        Get-WinGetPackageInfo "Notepad++" | Select-Object Id, Architectures, InstallerTypes
        Shows architecture and installer type availability.

    .NOTES
        Author: Mark Ringo
        Version: 2.0.0
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Name', 'ApplicationName', 'AppName')]
        [string]$DisplayName,

        [Parameter()]
        [Alias('Vendor', 'Author')]
        [string]$Publisher,

        [Parameter()]
        [Alias('Id', 'WinGetId')]
        [string]$PackageId,

        [Parameter()]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = $Script:DefaultTimeout
    )

    begin {
        Write-Verbose "Starting WinGet package info lookup..."
    }

    process {
        Write-Verbose "Searching for package info: $DisplayName"
        
        # Default "not found" response
        $notFoundResult = [PSCustomObject]@{
            Id               = $null
            Name             = $DisplayName
            Publisher        = $null
            Description      = $null
            Homepage         = $null
            License          = $null
            Tags             = $null
            Versions         = $null
            LatestVersion    = $null
            Architectures    = $null
            InstallerTypes   = $null
            AvailableScopes  = $null
            Has64BitInstaller = $false
            Found            = $false
        }
        
        try {
            $packages = Get-CachedApiResponse -SearchTerm $DisplayName -Publisher $Publisher -PackageId $PackageId -TimeoutSeconds $TimeoutSeconds
            
            if (-not $packages -or $packages.Count -eq 0) {
                Write-Verbose "Package not found: $DisplayName"
                return $notFoundResult
            }
            
            $bestMatch = Get-BestPackageMatch -Packages $packages -SearchTerm $DisplayName -Publisher $Publisher -PackageId $PackageId
            
            if (-not $bestMatch) {
                Write-Verbose "No matching package found for: $DisplayName"
                return $notFoundResult
            }
            
            $latest = $bestMatch.Latest
            
            # Get installer metadata
            $metadata = Get-InstallerMetadata -Package $bestMatch
            
            # If no installer metadata in search results, try fetching full manifest
            if ($metadata.Architectures.Count -eq 0 -and $bestMatch.Id) {
                Write-Verbose "Fetching full manifest for complete installer data..."
                $fullManifest = Get-PackageManifestDetails -PackageId $bestMatch.Id -TimeoutSeconds $TimeoutSeconds
                if ($fullManifest) {
                    $metadata = Get-InstallerMetadata -Package $fullManifest
                }
            }
            
            # Get versions and determine latest
            $versions = @()
            if ($bestMatch.Versions) {
                $versions = $bestMatch.Versions
            }
            $latestVersion = if ($versions.Count -gt 0) { 
                Get-WinGetLatestVersion -Versions $versions 
            } else { 
                $null 
            }
            
            $result = [PSCustomObject]@{
                Id                = $bestMatch.Id
                Name              = $latest.Name
                Publisher         = $latest.Publisher
                Description       = $latest.Description
                Homepage          = $latest.Homepage
                License           = $latest.License
                Tags              = if ($latest.Tags) { $latest.Tags -join ', ' } else { $null }
                Versions          = if ($versions) { $versions -join ', ' } else { $null }
                LatestVersion     = $latestVersion
                Architectures     = if ($metadata.Architectures) { $metadata.Architectures -join ', ' } else { $null }
                InstallerTypes    = if ($metadata.InstallerTypes) { $metadata.InstallerTypes -join ', ' } else { $null }
                AvailableScopes   = if ($metadata.Scopes) { $metadata.Scopes -join ', ' } else { 'machine' }
                Has64BitInstaller = ($metadata.Has64Bit -or $metadata.HasArm64)
                Found             = $true
            }
            
            Write-Verbose "Package info retrieved: $($result.Name) ($($result.Id))"
            return $result
        }
        catch {
            Write-Verbose "Error searching for $DisplayName : $($_.Exception.Message)"
            Write-Warning "Error querying WinGet API: $($_.Exception.Message)"
            return $null
        }
    }

    end {
        Write-Verbose "Package info lookup completed."
    }
}
#endregion

#region Public Functions - CLI-Based Operations

function Test-WinGet64BitAvailable {
    <#
    .SYNOPSIS
        Tests if a WinGet package has a 64-bit installer using the local WinGet CLI.

    .DESCRIPTION
        Uses the local WinGet command-line tool to definitively check if a package
        has an x64 architecture installer available. This queries the actual
        package manifest via the CLI.
        
        Note: Requires WinGet CLI to be installed locally.

    .PARAMETER PackageId
        The WinGet package ID to check.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for the WinGet command. Default is 30.

    .OUTPUTS
        System.Boolean
        Returns $true if x64 installer is available, $false otherwise.

    .EXAMPLE
        Test-WinGet64BitAvailable -PackageId "RARLab.WinRAR"
        Returns $true if WinRAR has an x64 installer.

    .NOTES
        Author: Mark Ringo
        Version: 2.0.0
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Id', 'WinGetId')]
        [string]$PackageId,

        [Parameter()]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30
    )

    begin {
        if (-not $Script:WinGetCliAvailable) {
            Write-Warning "WinGet CLI not found. Cannot verify 64-bit availability via CLI."
        }
    }

    process {
        if (-not $Script:WinGetCliAvailable) {
            return $false
        }

        Write-Verbose "Checking x64 availability via CLI for: $PackageId"
        
        $arguments = @(
            'show',
            '--id', $PackageId,
            '--architecture', 'x64',
            '--accept-source-agreements',
            '--disable-interactivity'
        )
        
        $result = Invoke-WinGetCliCommand -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
        
        if (-not $result.Success -and $result.ExitCode -eq -1) {
            Write-Warning "WinGet command failed for $PackageId : $($result.StdErr)"
            return $false
        }
        
        $output = $result.StdOut
        $exitCode = $result.ExitCode
        
        if ($exitCode -eq 0 -and $output -match 'Found.*\[') {
            if ($output -match 'No applicable installer found') {
                Write-Verbose "Package found but no x64 installer: $PackageId"
                return $false
            }
            
            if ($output -match 'Installer Url:|Installer Type:') {
                Write-Verbose "64-bit version available: $PackageId"
                return $true
            }
        }
        
        Write-Verbose "No 64-bit version found: $PackageId"
        return $false
    }
}

function Get-WinGet64BitPackageId {
    <#
    .SYNOPSIS
        Gets the 64-bit package ID for an application.

    .DESCRIPTION
        Handles both scenarios:
        1. Package has x64 installer in same package (returns same ID)
        2. Package has separate 32/64-bit packages (returns 64-bit variant ID)

    .PARAMETER PackageId
        The WinGet package ID to check.

    .PARAMETER TimeoutSeconds
        Maximum time for WinGet commands. Default is 30.

    .OUTPUTS
        System.String
        Returns package ID that provides 64-bit installation, or $null.

    .EXAMPLE
        Get-WinGet64BitPackageId -PackageId "Adobe.Acrobat.Reader.32-bit"
        Returns "Adobe.Acrobat.Reader.64-bit"

    .EXAMPLE
        Get-WinGet64BitPackageId -PackageId "7zip.7zip"
        Returns "7zip.7zip" (same package has x64)

    .NOTES
        Author: Mark Ringo
        Version: 2.0.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Id', 'WinGetId')]
        [string]$PackageId,

        [Parameter()]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30
    )

    process {
        Write-Verbose "Checking for 64-bit package: $PackageId"
        
        # First check if current package has x64
        if (Test-WinGet64BitAvailable -PackageId $PackageId -TimeoutSeconds $TimeoutSeconds) {
            Write-Verbose "Package $PackageId has x64 installer"
            return $PackageId
        }
        
        # Check for 64-bit variant package
        $potential64BitId = $null
        
        if ($PackageId -match '\.32-bit$') {
            $potential64BitId = $PackageId -replace '\.32-bit$', '.64-bit'
        }
        elseif ($PackageId -match '-32-bit$') {
            $potential64BitId = $PackageId -replace '-32-bit$', '-64-bit'
        }
        elseif ($PackageId -match '\.x86$') {
            $potential64BitId = $PackageId -replace '\.x86$', '.x64'
        }
        elseif ($PackageId -match '-x86$') {
            $potential64BitId = $PackageId -replace '-x86$', '-x64'
        }
        elseif ($PackageId -match '32$') {
            $potential64BitId = $PackageId -replace '32$', '64'
        }
        
        if ($potential64BitId) {
            Write-Verbose "Checking 64-bit variant: $potential64BitId"
            if (Test-WinGet64BitAvailable -PackageId $potential64BitId -TimeoutSeconds $TimeoutSeconds) {
                Write-Verbose "Found 64-bit variant: $potential64BitId"
                return $potential64BitId
            }
        }
        
        Write-Verbose "No 64-bit package available for: $PackageId"
        return $null
    }
}

function Find-WinGetPackageByProductCode {
    <#
    .SYNOPSIS
        Finds a WinGet package by MSI ProductCode GUID.

    .DESCRIPTION
        Searches for a WinGet package using an MSI ProductCode.
        This is useful for correlating installed applications (from registry)
        with WinGet packages for upgrade scenarios.
        
        Requires WinGet CLI to be installed locally.

    .PARAMETER ProductCode
        The MSI ProductCode GUID to search for.
        Can include or exclude curly braces.

    .PARAMETER TimeoutSeconds
        Maximum time for the WinGet command. Default is 30.

    .OUTPUTS
        PSCustomObject with package details, or $null if not found.

    .EXAMPLE
        Find-WinGetPackageByProductCode -ProductCode "{AC76BA86-7AD7-1033-7B44-AC0F074E4100}"
        Searches for Adobe Acrobat Reader by its ProductCode.

    .EXAMPLE
        $installed = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        $installed | Where-Object { $_.PSChildName -match '^\{' } | ForEach-Object {
            Find-WinGetPackageByProductCode -ProductCode $_.PSChildName
        }
        Searches WinGet for all installed MSI products.

    .NOTES
        Author: Mark Ringo
        Version: 2.0.0
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('GUID', 'MSIProductCode')]
        [string]$ProductCode,

        [Parameter()]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30
    )

    begin {
        if (-not $Script:WinGetCliAvailable) {
            Write-Warning "WinGet CLI not found. ProductCode search requires WinGet CLI."
        }
    }

    process {
        if (-not $Script:WinGetCliAvailable) {
            return $null
        }

        # Normalize ProductCode (ensure curly braces)
        $normalizedCode = $ProductCode.Trim()
        if ($normalizedCode -notmatch '^\{') {
            $normalizedCode = "{$normalizedCode"
        }
        if ($normalizedCode -notmatch '\}$') {
            $normalizedCode = "$normalizedCode}"
        }

        Write-Verbose "Searching for ProductCode: $normalizedCode"
        
        $arguments = @(
            'search',
            '--product-code', $normalizedCode,
            '--accept-source-agreements',
            '--disable-interactivity'
        )
        
        $result = Invoke-WinGetCliCommand -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
        
        if (-not $result.Success) {
            Write-Verbose "WinGet search failed: $($result.StdErr)"
            return $null
        }
        
        $output = $result.StdOut
        
        # Parse WinGet CLI output
        # Format is typically: Name  Id  Version  Source
        $lines = $output -split "`n" | Where-Object { $_.Trim() -ne '' }
        
        # Find the data line (skip header and separator)
        $dataLine = $null
        $foundHeader = $false
        foreach ($line in $lines) {
            if ($line -match '^-+') {
                $foundHeader = $true
                continue
            }
            if ($foundHeader -and $line -match '\S') {
                $dataLine = $line
                break
            }
        }
        
        if (-not $dataLine) {
            Write-Verbose "No package found for ProductCode: $normalizedCode"
            return $null
        }
        
        # Parse the data line (columns are space-separated, variable width)
        # This is fragile but WinGet doesn't offer JSON output for search
        $parts = $dataLine -split '\s{2,}'
        
        if ($parts.Count -ge 3) {
            $result = [PSCustomObject]@{
                Name        = $parts[0].Trim()
                Id          = $parts[1].Trim()
                Version     = $parts[2].Trim()
                Source      = if ($parts.Count -ge 4) { $parts[3].Trim() } else { 'winget' }
                ProductCode = $normalizedCode
            }
            
            Write-Verbose "Found package: $($result.Name) ($($result.Id))"
            return $result
        }
        
        return $null
    }
}
#endregion

#region Public Functions - Cache Management

function Clear-WinGetCache {
    <#
    .SYNOPSIS
        Clears the session-level WinGet API cache.

    .DESCRIPTION
        Clears all cached API responses (package searches and manifest data)
        and resets cache statistics.

    .EXAMPLE
        Clear-WinGetCache
        Clears all cached data.

    .NOTES
        Author: Mark Ringo
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param()
    
    $packageCount = $Script:PackageCache.Count
    $manifestCount = $Script:ManifestCache.Count
    
    $Script:PackageCache.Clear()
    $Script:ManifestCache.Clear()
    $Script:CacheHits = 0
    $Script:CacheMisses = 0
    
    Write-Verbose "Cleared $packageCount package cache entries and $manifestCount manifest cache entries"
}

function Get-WinGetCacheStatistics {
    <#
    .SYNOPSIS
        Returns cache statistics for the current session.

    .DESCRIPTION
        Returns information about cache performance including hits, misses,
        and efficiency percentage.

    .OUTPUTS
        PSCustomObject with cache statistics.

    .EXAMPLE
        Get-WinGetCacheStatistics

    .NOTES
        Author: Mark Ringo
        Version: 2.0.0
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    $totalRequests = $Script:CacheHits + $Script:CacheMisses
    $efficiency = if ($totalRequests -gt 0) { 
        [math]::Round(($Script:CacheHits / $totalRequests) * 100, 2) 
    } else { 
        0 
    }
    
    [PSCustomObject]@{
        PackageCacheEntries  = $Script:PackageCache.Count
        ManifestCacheEntries = $Script:ManifestCache.Count
        CacheHits            = $Script:CacheHits
        CacheMisses          = $Script:CacheMisses
        TotalRequests        = $totalRequests
        EfficiencyPct        = $efficiency
        ApiCallsSaved        = $Script:CacheHits
    }
}

function Initialize-WinGetPackageCache {
    <#
    .SYNOPSIS
        Pre-fetches package information for multiple applications.

    .DESCRIPTION
        Makes API calls for all provided search terms to pre-populate the cache.
        Includes throttling to avoid API rate limits.

    .PARAMETER SearchTerms
        Array of application names to pre-fetch.

    .PARAMETER Publisher
        Optional publisher filter to apply to all searches.

    .PARAMETER TimeoutSeconds
        Timeout per API request. Default is 30.

    .PARAMETER ThrottleDelayMs
        Milliseconds between API calls. Default is 100.

    .EXAMPLE
        Initialize-WinGetPackageCache -SearchTerms @("7-Zip", "Notepad++", "VLC")
        Pre-fetches multiple packages.

    .NOTES
        Author: Mark Ringo
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string[]]$SearchTerms,

        [Parameter()]
        [string]$Publisher,

        [Parameter()]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30,

        [Parameter()]
        [ValidateRange(0, 5000)]
        [int]$ThrottleDelayMs = 100
    )

    begin {
        $allTerms = @()
    }

    process {
        $allTerms += $SearchTerms
    }

    end {
        # Get unique terms not already cached
        $uniqueTerms = $allTerms | 
            ForEach-Object { $_.Trim() } | 
            Select-Object -Unique |
            Where-Object { 
                $cacheKey = Get-CacheKey -SearchTerm $_ -Publisher $Publisher -PackageId ''
                -not $Script:PackageCache.ContainsKey($cacheKey)
            }

        if ($uniqueTerms.Count -eq 0) {
            Write-Verbose "All search terms already cached"
            return
        }

        Write-Verbose "Pre-fetching $($uniqueTerms.Count) packages..."
        $fetched = 0
        $total = $uniqueTerms.Count

        foreach ($term in $uniqueTerms) {
            $fetched++
            Write-Progress -Activity "Pre-fetching WinGet packages" -Status "$fetched of $total - $term" -PercentComplete (($fetched / $total) * 100)
            
            $null = Get-CachedApiResponse -SearchTerm $term -Publisher $Publisher -TimeoutSeconds $TimeoutSeconds
            
            if ($ThrottleDelayMs -gt 0 -and $fetched -lt $total) {
                Start-Sleep -Milliseconds $ThrottleDelayMs
            }
        }

        Write-Progress -Activity "Pre-fetching WinGet packages" -Completed
        Write-Verbose "Pre-fetch complete. Cache: $($Script:PackageCache.Count) packages, $($Script:ManifestCache.Count) manifests"
    }
}
#endregion

#region Module Exports
Export-ModuleMember -Function @(
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
#endregion
