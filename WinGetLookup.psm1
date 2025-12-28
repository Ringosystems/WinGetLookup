#Requires -Version 5.1

<#
.SYNOPSIS
    WinGetLookup PowerShell Module - Query WinGet package availability.

.DESCRIPTION
    This module provides functions to query the WinGet (Windows Package Manager) repository
    to determine if packages exist. It uses the winget.run API for package lookups.
    
    Features:
    - Smart matching algorithm to find the best package match
    - Publisher and PackageId filtering for precise matching
    - 64-bit version detection
    - Session-level caching to minimize API calls
    
    SUPPORTED PLATFORMS:
    - Windows 10 version 1709 (build 16299) or later
    - Windows 11 (all versions)
    - Windows Server 2019 (build 17763) or later
    - Windows Server 2022 (all versions)
    - PowerShell 5.1 (Windows PowerShell) and PowerShell 7+ (PowerShell Core)
    
    Note: The module's API-based functions work on any platform with internet access.
    The WinGet CLI-based functions (Test-WinGet64BitAvailable) require WinGet to be
    installed, which is only available on supported Windows versions.

.NOTES
    Module Name: WinGetLookup
    Author: Ringo
    Version: 1.7.0
    Date: December 27, 2025
    
    This module does not require WinGet to be installed locally as it queries
    the winget.run web API directly.
    
    API calls are cached for the duration of the PowerShell session to improve
    performance when querying multiple similar applications.
#>

#region Private Variables
$Script:WinGetApiBaseUrl = 'https://api.winget.run/v2'
$Script:DefaultTimeout = 30
$Script:DefaultTakeCount = 10  # Fetch multiple results for smart matching

# Session-level cache for API responses to minimize redundant calls
# Key: URL-encoded search term, Value: API response (packages array)
$Script:PackageCache = @{}
$Script:CacheHits = 0
$Script:CacheMisses = 0

# WinGet CLI path - cached at module load for performance
$Script:WinGetCliPath = $null
$Script:WinGetCliAvailable = $false
#endregion

#region Module Initialization
# Find and cache WinGet CLI path at module load (Improvement #1)
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

# Initialize WinGet CLI path at module load
Initialize-WinGetCliPath
#endregion

#region Private Functions

function Invoke-WinGetCliCommand {
    <#
    .SYNOPSIS
        Executes a WinGet CLI command with timeout and proper output handling.
    .DESCRIPTION
        Reusable helper for running WinGet commands with consistent error handling.
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
        
        $process.Start() | Out-Null
        
        # Read output asynchronously
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        
        # Wait for process with timeout
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

function Get-CachedApiResponse {
    <#
    .SYNOPSIS
        Retrieves cached API response or makes a new API call and caches the result.
    
    .DESCRIPTION
        Implements session-level caching to reduce redundant API calls.
        Cache persists for the lifetime of the PowerShell session or until
        Clear-WinGetCache is called.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SearchTerm,
        
        [int]$TimeoutSeconds = $Script:DefaultTimeout
    )
    
    # Create cache key from search term
    $cacheKey = $SearchTerm.ToLowerInvariant().Trim()
    
    # Check if we have a cached response
    if ($Script:PackageCache.ContainsKey($cacheKey)) {
        $Script:CacheHits++
        Write-Verbose "Cache HIT for '$SearchTerm' (Total hits: $($Script:CacheHits))"
        return $Script:PackageCache[$cacheKey]
    }
    
    # Cache miss - make API call
    $Script:CacheMisses++
    Write-Verbose "Cache MISS for '$SearchTerm' - calling API (Total misses: $($Script:CacheMisses))"
    
    try {
        # URL encode the search term
        $encodedName = [System.Uri]::EscapeDataString($SearchTerm)
        
        # Build the API URL
        $takeCount = $Script:DefaultTakeCount
        $apiUrl = "$Script:WinGetApiBaseUrl/packages?name=$encodedName&ensureContains=true&take=$takeCount"
        
        Write-Verbose "API URL: $apiUrl"
        
        # Configure request parameters
        $requestParams = @{
            Uri             = $apiUrl
            Method          = 'Get'
            TimeoutSec      = $TimeoutSeconds
            ErrorAction     = 'Stop'
            UseBasicParsing = $true
        }
        
        # Make the API request
        $response = Invoke-RestMethod @requestParams
        
        # Parse response
        $packages = $null
        
        if ($response -is [string]) {
            $parsed = $response | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
            if ($parsed -and $parsed.Packages) {
                $packages = $parsed.Packages
            }
        } elseif ($response.Packages) {
            $packages = $response.Packages
        }
        
        # Cache the result (even if empty - avoids repeated failed lookups)
        $Script:PackageCache[$cacheKey] = $packages
        
        return $packages
    }
    catch {
        Write-Verbose "API error for '$SearchTerm': $($_.Exception.Message)"
        # Cache the failure as empty result to avoid repeated failed calls
        $Script:PackageCache[$cacheKey] = @()
        return @()
    }
}

function Get-BestPackageMatch {
    <#
    .SYNOPSIS
        Scores and selects the best matching package from multiple API results.
    .DESCRIPTION
        Implements smart matching with quality thresholds to avoid false positives.
        Requires packages to have meaningful relevance to the search term.
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
    
    # If PackageId is specified, find exact match
    if ($PackageId) {
        $exactMatch = $Packages | Where-Object { $_.Id -eq $PackageId } | Select-Object -First 1
        return $exactMatch
    }
    
    $scoredPackages = @()
    $searchTermLower = $SearchTerm.ToLower()
    $publisherLower = if ($Publisher) { $Publisher.ToLower() } else { $null }
    
    # Extract the primary word from search term for relevance check
    # This prevents "TeamViewer 15" from matching "115Chrome"
    # Filter out pure version numbers (all digits with dots) but keep things like "7-Zip"
    $searchWords = $searchTermLower -split '\s+' | Where-Object { 
        # Keep words that are NOT pure version numbers (e.g., keep "7-zip" but filter "24.09")
        $_ -notmatch '^\d+(\.\d+)+$' -and $_.Length -gt 0
    }
    $primaryWord = if ($searchWords.Count -gt 0) { 
        # Use the first meaningful word as the primary match requirement
        $searchWords[0]
    } else { 
        # Fallback to full search term if no words remain
        $searchTermLower 
    }
    
    foreach ($pkg in $Packages) {
        $score = 0
        $pkgId = $pkg.Id
        $pkgName = if ($pkg.Latest) { $pkg.Latest.Name } else { $pkg.Name }
        $pkgPublisher = if ($pkg.Latest) { $pkg.Latest.Publisher } else { $pkg.Publisher }
        
        $pkgIdLower = if ($pkgId) { $pkgId.ToLower() } else { '' }
        $pkgNameLower = if ($pkgName) { $pkgName.ToLower() } else { '' }
        $pkgPublisherLower = if ($pkgPublisher) { $pkgPublisher.ToLower() } else { '' }
        
        # CRITICAL: Package must contain the primary search word to be considered
        # This prevents completely unrelated packages from being returned
        $hasPrimaryWord = ($pkgIdLower -like "*$primaryWord*") -or 
                          ($pkgNameLower -like "*$primaryWord*") -or
                          ($pkgPublisherLower -like "*$primaryWord*")
        
        if (-not $hasPrimaryWord) {
            # Skip packages that don't contain the primary search word at all
            continue
        }
        
        # Base score for having the primary word
        $score += 5
        
        # +100: Package ID = SearchTerm.SearchTerm pattern (e.g., "PuTTY.PuTTY", "7zip.7zip")
        $expectedId = "$searchTermLower.$searchTermLower"
        if ($pkgIdLower -eq $expectedId) {
            $score += 100
        }
        
        # +75: Publisher matches (when -Publisher specified)
        if ($publisherLower -and $pkgPublisherLower) {
            if ($pkgPublisherLower -eq $publisherLower) {
                $score += 75
            } elseif ($pkgPublisherLower -like "*$publisherLower*") {
                $score += 40
            }
        }
        
        # +50: Exact name match (case-insensitive)
        if ($pkgNameLower -eq $searchTermLower) {
            $score += 50
        }
        
        # +30: Name equals primary word exactly (e.g., "TeamViewer" matches name "TeamViewer")
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
    
    # Require a minimum score to return a match (prevents low-quality matches)
    $minScore = 10
    $best = $scoredPackages | Where-Object { $_.Score -ge $minScore } | 
            Sort-Object -Property Score -Descending | 
            Select-Object -First 1
    
    if ($best) {
        return $best.Package
    }
    
    return $null
}

function Test-64BitIndicators {
    <#
    .SYNOPSIS
        Checks if package has 64-bit indicators in its ID, name, or tags.
    #>
    param(
        [string]$PackageId,
        [string]$PackageName,
        [array]$Tags
    )
    
    # Check package ID for 64-bit indicators
    if ($PackageId -match '64[-.]?bit|x64|win64|\.64|amd64') {
        return $true
    }
    
    # Check package name for 64-bit indicators
    if ($PackageName -match '64[-\s]?bit|x64|\(64\)|win64|amd64') {
        return $true
    }
    
    # Check tags for 64-bit/x64 indicators
    if ($Tags) {
        foreach ($tag in $Tags) {
            if ($tag -match '^(64-?bit|x64|amd64|win64)$') {
                return $true
            }
        }
    }
    
    # Many modern apps default to 64-bit, check for known 64-bit package patterns
    # These are well-known packages that provide 64-bit versions
    $known64BitPatterns = @(
        '7zip\.7zip',
        'Notepad\+\+\.Notepad\+\+',
        'VideoLAN\.VLC',
        'Mozilla\.Firefox',
        'Google\.Chrome',
        'Adobe\.Acrobat\.Reader\.64-bit',
        'Microsoft\.VisualStudioCode',
        'Git\.Git',
        'Python\.Python',
        'OpenJS\.NodeJS',
        'voidtools\.Everything',
        'WinSCP\.WinSCP',
        'PuTTY\.PuTTY',
        'Bitwarden\.Bitwarden',
        'KeePassXCTeam\.KeePassXC'
    )
    
    foreach ($pattern in $known64BitPatterns) {
        if ($PackageId -match $pattern) {
            return $true
        }
    }
    
    return $false
}

function Test-64BitPackageAvailable {
    <#
    .SYNOPSIS
        Parses API response string to check for 64-bit package availability.
    #>
    param(
        [string]$ResponseString
    )
    
    # Extract package ID from response
    $packageId = $null
    $packageName = $null
    $tags = @()
    
    if ($ResponseString -match '"Id"\s*:\s*"([^"]+)"') {
        $packageId = $Matches[1]
    }
    
    if ($ResponseString -match '"Name"\s*:\s*"([^"]+)"') {
        $packageName = $Matches[1]
    }
    
    # Extract tags array
    if ($ResponseString -match '"Tags"\s*:\s*\[([^\]]*)\]') {
        $tagsString = $Matches[1]
        $tags = [regex]::Matches($tagsString, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
    }
    
    return Test-64BitIndicators -PackageId $packageId -PackageName $packageName -Tags $tags
}
#endregion

#region Public Functions

function Test-WinGetPackage {
    <#
    .SYNOPSIS
        Tests if an application package exists in the WinGet repository.

    .DESCRIPTION
        Queries the winget.run API to determine if a package with the specified 
        display name exists in the Windows Package Manager (WinGet) repository.
        
        Uses smart matching to find the best package match when multiple results
        are returned. Supports filtering by publisher for precise matching.
        
        This function is useful for:
        - Validating if an application can be installed via WinGet
        - Checking package availability before automation scripts
        - Inventory assessment for application deployment planning

    .PARAMETER DisplayName
        The display name of the application to search for.
        This should be the common name of the application (e.g., "Notepad++", "7-Zip", "VLC").
        The search is case-insensitive and uses partial matching.

    .PARAMETER Publisher
        Optional publisher name to filter results for more precise matching.
        Useful when multiple packages share similar names.
        Example: -Publisher "Simon Tatham" to specifically match PuTTY.

    .PARAMETER PackageId
        Optional exact WinGet package ID for direct matching.
        When specified, DisplayName is still used for the search but only the
        package with this exact ID will be considered a match.
        Example: -PackageId "PuTTY.PuTTY"

    .PARAMETER Require64Bit
        When specified, returns 1 only if a 64-bit version of the package is available.
        The function checks if the package ID or name contains '64', 'x64', or 'win64' indicators,
        or if the package has x64 architecture tags.

    .PARAMETER TimeoutSeconds
        The timeout in seconds for the API request.
        Default is 30 seconds.

    .OUTPUTS
        System.Int32
        Returns 1 if the package is found in the WinGet repository (and meets all requirements).
        Returns 0 if the package is not found, doesn't match criteria, or an error occurs.

    .EXAMPLE
        Test-WinGetPackage -DisplayName "Visual Studio Code"
        
        Returns 1 if Visual Studio Code is available in WinGet, 0 otherwise.

    .EXAMPLE
        Test-WinGetPackage "Notepad++"
        
        Uses positional parameter to check if Notepad++ is available.
        Returns 1 if found.

    .EXAMPLE
        Test-WinGetPackage -DisplayName "PuTTY" -Publisher "Simon Tatham"
        
        Returns 1 only if PuTTY by Simon Tatham is found (not MTPuTTY or other variants).

    .EXAMPLE
        Test-WinGetPackage -DisplayName "PuTTY" -PackageId "PuTTY.PuTTY"
        
        Returns 1 only if the exact package ID "PuTTY.PuTTY" is found.

    .EXAMPLE
        $exists = Test-WinGetPackage "7-Zip"
        if ($exists -eq 1) {
            Write-Host "7-Zip is available for installation via WinGet"
        }
        
        Demonstrates using the return value in conditional logic.

    .EXAMPLE
        @("Notepad++", "7-Zip", "VLC", "FakeApp123") | ForEach-Object {
            [PSCustomObject]@{
                Application = $_
                Available   = Test-WinGetPackage $_
            }
        }
        
        Checks multiple applications and creates a report of availability.

    .EXAMPLE
        Test-WinGetPackage -DisplayName "Adobe Acrobat Reader" -Require64Bit
        
        Returns 1 only if a 64-bit version of Adobe Acrobat Reader is available in WinGet.

    .EXAMPLE
        $has64Bit = Test-WinGetPackage "7-Zip" -Require64Bit
        if ($has64Bit -eq 1) {
            Write-Host "64-bit version is available"
        }
        
        Checks specifically for 64-bit availability.

    .NOTES
        Author: Ringo
        Version: 1.3.0
        
        This function uses the winget.run API which is a third-party service.
        It does not require WinGet to be installed locally.
        
        Caching: API responses are cached for the session to minimize redundant
        calls. Use Clear-WinGetCache to reset the cache if needed.
        
        Smart Matching: When multiple packages match, the function scores results
        based on name similarity, publisher match, and package ID patterns to
        return the most relevant match.
        
        API Rate Limiting: The winget.run API may have rate limits. For bulk
        operations, consider adding delays between requests.

    .LINK
        https://winget.run

    .LINK
        https://docs.microsoft.com/en-us/windows/package-manager/winget/
    #>

    [CmdletBinding()]
    [OutputType([System.Int32])]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "The display name of the application to search for."
        )]
        [ValidateNotNullOrEmpty()]
        [Alias('Name', 'ApplicationName', 'AppName')]
        [string]$DisplayName,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Publisher name to filter results for precise matching."
        )]
        [Alias('Vendor', 'Author')]
        [string]$Publisher,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Exact WinGet package ID for direct matching."
        )]
        [Alias('Id', 'WinGetId')]
        [string]$PackageId,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Only return 1 if a 64-bit version is available."
        )]
        [switch]$Require64Bit,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Timeout in seconds for the API request."
        )]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = $Script:DefaultTimeout
    )

    begin {
        Write-Verbose "Starting WinGet package lookup..."
        if ($Require64Bit) {
            Write-Verbose "64-bit version requirement enabled"
        }
        if ($Publisher) {
            Write-Verbose "Publisher filter: $Publisher"
        }
        if ($PackageId) {
            Write-Verbose "Package ID filter: $PackageId"
        }
    }

    process {
        Write-Verbose "Searching for package: $DisplayName"
        
        try {
            # Use cached API response or make new call
            $packages = Get-CachedApiResponse -SearchTerm $DisplayName -TimeoutSeconds $TimeoutSeconds
            
            if (-not $packages -or $packages.Count -eq 0) {
                Write-Verbose "Package not found: $DisplayName"
                return 0
            }
            
            # Use smart matching to find best package
            $bestMatch = Get-BestPackageMatch -Packages $packages -SearchTerm $DisplayName -Publisher $Publisher -PackageId $PackageId
            
            if (-not $bestMatch) {
                Write-Verbose "No matching package found for: $DisplayName"
                return 0
            }
            
            $matchedId = $bestMatch.Id
            $matchedName = if ($bestMatch.Latest) { $bestMatch.Latest.Name } else { $bestMatch.Name }
            Write-Verbose "Best match: $matchedName ($matchedId)"
            
            # If 64-bit is required, check for 64-bit indicators
            if ($Require64Bit) {
                $pkgTags = if ($bestMatch.Latest -and $bestMatch.Latest.Tags) { $bestMatch.Latest.Tags } else { @() }
                $has64Bit = Test-64BitIndicators -PackageId $matchedId -PackageName $matchedName -Tags $pkgTags
                
                if ($has64Bit) {
                    Write-Verbose "64-bit version confirmed for: $matchedName"
                    return 1
                } else {
                    Write-Verbose "No 64-bit version found for: $matchedName"
                    return 0
                }
            }
            
            return 1
        }
        catch [System.Net.WebException] {
            Write-Verbose "Network error while searching for $DisplayName : $($_.Exception.Message)"
            Write-Warning "Network error occurred while querying WinGet API for '$DisplayName'"
            return 0
        }
        catch {
            Write-Verbose "Error searching for $DisplayName : $($_.Exception.Message)"
            Write-Warning "Error occurred while querying WinGet API: $($_.Exception.Message)"
            return 0
        }
    }

    end {
        Write-Verbose "WinGet package lookup completed."
    }
}

function Get-WinGetPackageInfo {
    <#
    .SYNOPSIS
        Retrieves detailed information about a WinGet package.

    .DESCRIPTION
        Queries the winget.run API to retrieve detailed information about a package
        including its WinGet ID, publisher, description, available versions, and more.
        
        Uses smart matching to find the best package match when multiple results
        are returned. Supports filtering by publisher for precise matching.

    .PARAMETER DisplayName
        The display name of the application to search for.

    .PARAMETER Publisher
        Optional publisher name to filter results for more precise matching.
        Useful when multiple packages share similar names.

    .PARAMETER PackageId
        Optional exact WinGet package ID for direct matching.
        When specified, only the package with this exact ID will be returned.

    .PARAMETER TimeoutSeconds
        The timeout in seconds for the API request.
        Default is 30 seconds.

    .OUTPUTS
        PSCustomObject
        Returns an object with package details if found, or $null if not found.

    .EXAMPLE
        Get-WinGetPackageInfo -DisplayName "Notepad++"
        
        Returns detailed information about the Notepad++ package.

    .EXAMPLE
        Get-WinGetPackageInfo "7-Zip" | Select-Object Id, Name, Publisher
        
        Gets 7-Zip info and displays specific properties.

    .EXAMPLE
        Get-WinGetPackageInfo -DisplayName "PuTTY" -Publisher "Simon Tatham"
        
        Returns info for PuTTY by Simon Tatham specifically.

    .EXAMPLE
        Get-WinGetPackageInfo -DisplayName "PuTTY" -PackageId "PuTTY.PuTTY"
        
        Returns info for the exact package ID "PuTTY.PuTTY".

    .NOTES
        Author: Ringo
        Version: 1.3.0

    .LINK
        https://winget.run
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "The display name of the application to search for."
        )]
        [ValidateNotNullOrEmpty()]
        [Alias('Name', 'ApplicationName', 'AppName')]
        [string]$DisplayName,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Publisher name to filter results for precise matching."
        )]
        [Alias('Vendor', 'Author')]
        [string]$Publisher,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Exact WinGet package ID for direct matching."
        )]
        [Alias('Id', 'WinGetId')]
        [string]$PackageId,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Timeout in seconds for the API request."
        )]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = $Script:DefaultTimeout
    )

    begin {
        Write-Verbose "Starting WinGet package info lookup..."
        if ($Publisher) {
            Write-Verbose "Publisher filter: $Publisher"
        }
        if ($PackageId) {
            Write-Verbose "Package ID filter: $PackageId"
        }
    }

    process {
        Write-Verbose "Searching for package info: $DisplayName"
        
        try {
            # Use cached API response or make new call
            $packages = Get-CachedApiResponse -SearchTerm $DisplayName -TimeoutSeconds $TimeoutSeconds
            
            if (-not $packages -or $packages.Count -eq 0) {
                Write-Verbose "Package not found: $DisplayName"
                return [PSCustomObject]@{
                    Id                = $null
                    Name              = $DisplayName
                    Publisher         = $null
                    Description       = $null
                    Homepage          = $null
                    License           = $null
                    Tags              = $null
                    Versions          = $null
                    Has64BitIndicator = $false
                    Found             = $false
                }
            }
            
            # Use smart matching to find best package
            $bestMatch = Get-BestPackageMatch -Packages $packages -SearchTerm $DisplayName -Publisher $Publisher -PackageId $PackageId
            
            if (-not $bestMatch) {
                Write-Verbose "No matching package found for: $DisplayName"
                return [PSCustomObject]@{
                    Id                = $null
                    Name              = $DisplayName
                    Publisher         = $null
                    Description       = $null
                    Homepage          = $null
                    License           = $null
                    Tags              = $null
                    Versions          = $null
                    Has64BitIndicator = $false
                    Found             = $false
                }
            }
            
            $latest = $bestMatch.Latest
            
            # Check for 64-bit indicators in package metadata
            $has64Bit = Test-64BitIndicators -PackageId $bestMatch.Id -PackageName $latest.Name -Tags $latest.Tags
            
            $result = [PSCustomObject]@{
                Id                = $bestMatch.Id
                Name              = $latest.Name
                Publisher         = $latest.Publisher
                Description       = $latest.Description
                Homepage          = $latest.Homepage
                License           = $latest.License
                Tags              = if ($latest.Tags) { $latest.Tags -join ', ' } else { $null }
                Versions          = if ($bestMatch.Versions) { $bestMatch.Versions -join ', ' } else { $null }
                Has64BitIndicator = $has64Bit
                Found             = $true
            }
            
            Write-Verbose "Package info retrieved: $($result.Name) ($($result.Id))"
            return $result
        }
        catch {
            Write-Verbose "Error searching for $DisplayName : $($_.Exception.Message)"
            Write-Warning "Error occurred while querying WinGet API: $($_.Exception.Message)"
            return $null
        }
    }

    end {
        Write-Verbose "WinGet package info lookup completed."
    }
}

function Clear-WinGetCache {
    <#
    .SYNOPSIS
        Clears the session-level WinGet API cache.

    .DESCRIPTION
        Clears all cached API responses and resets cache statistics.
        Use this if you need fresh data from the API or to free memory.

    .EXAMPLE
        Clear-WinGetCache
        
        Clears all cached WinGet package data.

    .EXAMPLE
        Clear-WinGetCache -Verbose
        
        Clears cache and shows how many entries were removed.

    .NOTES
        Author: Ringo
        Version: 1.3.0
    #>
    [CmdletBinding()]
    param()
    
    $entryCount = $Script:PackageCache.Count
    $Script:PackageCache.Clear()
    $Script:CacheHits = 0
    $Script:CacheMisses = 0
    
    Write-Verbose "Cleared $entryCount cached entries and reset statistics"
}

function Get-WinGetCacheStatistics {
    <#
    .SYNOPSIS
        Returns cache statistics for the current session.

    .DESCRIPTION
        Returns information about cache hits, misses, and efficiency
        to help understand API call reduction.

    .OUTPUTS
        PSCustomObject with cache statistics.

    .EXAMPLE
        Get-WinGetCacheStatistics
        
        Returns cache hit/miss counts and efficiency percentage.

    .EXAMPLE
        # After running multiple queries
        Get-WinGetCacheStatistics | Format-List
        
        Shows detailed cache performance.

    .NOTES
        Author: Ringo
        Version: 1.3.0
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
        CachedEntries    = $Script:PackageCache.Count
        CacheHits        = $Script:CacheHits
        CacheMisses      = $Script:CacheMisses
        TotalRequests    = $totalRequests
        EfficiencyPct    = $efficiency
        ApiCallsSaved    = $Script:CacheHits
    }
}

function Test-WinGet64BitAvailable {
    <#
    .SYNOPSIS
        Tests if a WinGet package has a 64-bit installer available using the local WinGet CLI.

    .DESCRIPTION
        Uses the local WinGet command-line tool to definitively check if a package
        has an x64 architecture installer available. This is more accurate than
        heuristic-based detection as it queries the actual package manifest.
        
        Note: This function requires WinGet to be installed locally.

    .PARAMETER PackageId
        The WinGet package ID to check (e.g., "RARLab.WinRAR", "7zip.7zip").

    .PARAMETER TimeoutSeconds
        Maximum time to wait for the WinGet command to complete.
        Default is 30 seconds.

    .OUTPUTS
        System.Boolean
        Returns $true if the package has an x64 installer available, $false otherwise.

    .EXAMPLE
        Test-WinGet64BitAvailable -PackageId "RARLab.WinRAR"
        
        Returns $true because WinRAR has an x64 installer.

    .EXAMPLE
        Test-WinGet64BitAvailable -PackageId "Adobe.Acrobat.Reader.32-bit"
        
        Returns $false because this package only has x86 installers.

    .EXAMPLE
        # Use with Get-WinGetPackageInfo for complete package analysis
        $pkg = Get-WinGetPackageInfo -DisplayName "WinRAR"
        if ($pkg.Found) {
            $has64 = Test-WinGet64BitAvailable -PackageId $pkg.Id
            Write-Host "$($pkg.Name): 64-bit available = $has64"
        }

    .NOTES
        Author: Ringo
        Version: 1.5.0
        
        This function requires WinGet (winget.exe) to be installed and accessible.
        Unlike other functions in this module that use the winget.run API,
        this function queries the local WinGet installation directly for
        accurate architecture information.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "The WinGet package ID to check for 64-bit availability."
        )]
        [ValidateNotNullOrEmpty()]
        [Alias('Id', 'WinGetId')]
        [string]$PackageId,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Timeout in seconds for the WinGet command."
        )]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30
    )

    begin {
        Write-Verbose "Checking 64-bit availability via WinGet CLI..."
        
        if (-not $Script:WinGetCliAvailable) {
            Write-Warning "WinGet (winget.exe) not found. Cannot verify 64-bit availability via CLI."
        } else {
            Write-Verbose "Using cached WinGet path: $($Script:WinGetCliPath)"
        }
    }

    process {
        if (-not $Script:WinGetCliAvailable) {
            Write-Verbose "WinGet CLI not available, returning false for: $PackageId"
            return $false
        }

        Write-Verbose "Checking x64 availability for: $PackageId"
        
        # Build arguments for winget show with x64 architecture
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
        
        # Check if package was found and has a valid installer
        # Exit code 0 with "Found" indicates package exists
        # Must also have installer info but NOT "No applicable installer found"
        if ($exitCode -eq 0 -and $output -match 'Found.*\[') {
            # Check for "No applicable installer found" which means no x64 installer exists
            if ($output -match 'No applicable installer found') {
                Write-Verbose "Package found but no x64 installer available for: $PackageId"
                return $false
            }
            
            # Check for valid installer information (Installer URL or Type)
            if ($output -match 'Installer Url:|Installer Type:') {
                Write-Verbose "64-bit version available for: $PackageId"
                return $true
            }
        }
        
        Write-Verbose "No 64-bit version found for: $PackageId (Exit code: $exitCode)"
        return $false
    }

    end {
        Write-Verbose "64-bit availability check completed."
    }
}

function Get-WinGet64BitPackageId {
    <#
    .SYNOPSIS
        Gets the 64-bit package ID for an application, handling both same-package and separate-package scenarios.

    .DESCRIPTION
        Some applications have both 32-bit and 64-bit installers in the same WinGet package (e.g., 7-Zip, WinRAR).
        Other applications have separate packages for each architecture (e.g., Adobe.Acrobat.Reader.32-bit vs .64-bit).
        
        This function handles both scenarios:
        1. If the package has an x64 installer, returns the same package ID
        2. If the package ID contains ".32-bit" or "-32-bit", checks for a ".64-bit" variant
        3. Returns the appropriate 64-bit package ID, or $null if none available

    .PARAMETER PackageId
        The WinGet package ID to check (e.g., "Adobe.Acrobat.Reader.32-bit", "7zip.7zip").

    .PARAMETER TimeoutSeconds
        Maximum time to wait for WinGet commands.
        Default is 30 seconds.

    .OUTPUTS
        System.String
        Returns the package ID that provides 64-bit installation, or $null if none available.

    .EXAMPLE
        Get-WinGet64BitPackageId -PackageId "Adobe.Acrobat.Reader.32-bit"
        
        Returns "Adobe.Acrobat.Reader.64-bit" because a separate 64-bit package exists.

    .EXAMPLE
        Get-WinGet64BitPackageId -PackageId "7zip.7zip"
        
        Returns "7zip.7zip" because the same package has an x64 installer.

    .EXAMPLE
        Get-WinGet64BitPackageId -PackageId "SomeApp.OnlyX86"
        
        Returns $null if no 64-bit version is available.

    .NOTES
        Author: Ringo
        Version: 1.5.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "The WinGet package ID to check."
        )]
        [ValidateNotNullOrEmpty()]
        [Alias('Id', 'WinGetId')]
        [string]$PackageId,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Timeout in seconds for WinGet commands."
        )]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30
    )

    process {
        Write-Verbose "Checking for 64-bit package variant of: $PackageId"
        
        # First, check if the current package has an x64 installer
        if (Test-WinGet64BitAvailable -PackageId $PackageId -TimeoutSeconds $TimeoutSeconds) {
            Write-Verbose "Package $PackageId has x64 installer available"
            return $PackageId
        }
        
        # Check if this is a 32-bit specific package that might have a 64-bit variant
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
            # Handle cases like "SomeApp32" -> "SomeApp64"
            $potential64BitId = $PackageId -replace '32$', '64'
        }
        
        if ($potential64BitId) {
            Write-Verbose "Checking for 64-bit variant package: $potential64BitId"
            
            # Verify the 64-bit variant package exists and has an x64 installer
            if (Test-WinGet64BitAvailable -PackageId $potential64BitId -TimeoutSeconds $TimeoutSeconds) {
                Write-Verbose "Found 64-bit variant package: $potential64BitId"
                return $potential64BitId
            }
        }
        
        Write-Verbose "No 64-bit package available for: $PackageId"
        return $null
    }
}

function Initialize-WinGetPackageCache {
    <#
    .SYNOPSIS
        Pre-fetches package information for multiple applications to warm the cache.

    .DESCRIPTION
        Improvement #3: Batch API lookups
        Makes API calls for all provided search terms to pre-populate the cache.
        Subsequent calls to Get-WinGetPackageInfo or Test-WinGetPackage will use cached data.
        
        This is more efficient than making individual calls when processing many applications.

    .PARAMETER SearchTerms
        Array of application names to pre-fetch from the WinGet API.

    .PARAMETER TimeoutSeconds
        Timeout in seconds for each API request. Default is 30.

    .PARAMETER ThrottleDelayMs
        Milliseconds to wait between API calls to avoid rate limiting. Default is 100.

    .EXAMPLE
        $apps = @("7-Zip", "Notepad++", "VLC", "WinRAR")
        Initialize-WinGetPackageCache -SearchTerms $apps
        
        Pre-fetches all packages, then subsequent lookups are instant.

    .EXAMPLE
        $installed = Get-Installed32BitApplications
        Initialize-WinGetPackageCache -SearchTerms ($installed.DisplayName)
        
        Pre-warms cache with all installed application names.

    .NOTES
        Author: Ringo
        Version: 1.7.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string[]]$SearchTerms,

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
        # Deduplicate and normalize search terms
        $uniqueTerms = $allTerms | 
            ForEach-Object { $_.ToLowerInvariant().Trim() } | 
            Select-Object -Unique |
            Where-Object { -not $Script:PackageCache.ContainsKey($_) }  # Skip already cached

        if ($uniqueTerms.Count -eq 0) {
            Write-Verbose "All search terms already cached, nothing to prefetch"
            return
        }

        Write-Verbose "Pre-fetching $($uniqueTerms.Count) packages to cache..."
        $fetched = 0
        $total = $uniqueTerms.Count

        foreach ($term in $uniqueTerms) {
            $fetched++
            Write-Progress -Activity "Pre-fetching WinGet packages" -Status "$fetched of $total - $term" -PercentComplete (($fetched / $total) * 100)
            
            # This will cache the result
            $null = Get-CachedApiResponse -SearchTerm $term -TimeoutSeconds $TimeoutSeconds
            
            # Throttle to avoid rate limiting
            if ($ThrottleDelayMs -gt 0 -and $fetched -lt $total) {
                Start-Sleep -Milliseconds $ThrottleDelayMs
            }
        }

        Write-Progress -Activity "Pre-fetching WinGet packages" -Completed
        Write-Verbose "Pre-fetch complete. Cache now contains $($Script:PackageCache.Count) entries."
    }
}

#endregion

#region Module Exports
Export-ModuleMember -Function @(
    'Test-WinGetPackage',
    'Get-WinGetPackageInfo',
    'Clear-WinGetCache',
    'Get-WinGetCacheStatistics',
    'Test-WinGet64BitAvailable',
    'Get-WinGet64BitPackageId',
    'Initialize-WinGetPackageCache'
)
#endregion
