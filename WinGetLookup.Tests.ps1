#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester v5 tests for the WinGetLookup PowerShell module.

.DESCRIPTION
    Comprehensive test suite for the WinGetLookup module including:
    - Unit tests with mocked API responses
    - Parameter validation tests
    - Error handling tests
    - Integration tests (optional, requires internet)

.NOTES
    Author: Ringo
    Version: 1.7.0
    Date: December 27, 2025
    
    Requires: Pester v5.0.0 or higher
    
    Run all tests:
        Invoke-Pester -Path .\WinGetLookup.Tests.ps1
    
    Run with detailed output:
        Invoke-Pester -Path .\WinGetLookup.Tests.ps1 -Output Detailed
    
    Run with code coverage:
        Invoke-Pester -Path .\WinGetLookup.Tests.ps1 -CodeCoverage .\WinGetLookup.psm1
    
    Run only unit tests (exclude integration):
        Invoke-Pester -Path .\WinGetLookup.Tests.ps1 -ExcludeTag 'Integration'
    
    Run only integration tests:
        Invoke-Pester -Path .\WinGetLookup.Tests.ps1 -Tag 'Integration'
#>

BeforeAll {
    # Import the module before all tests
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'WinGetLookup.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop
    
    # Define mock responses for API calls
    $Script:MockFoundResponse = '{"Packages":[{"Id":"Test.Package","Versions":["1.0"],"Latest":{"Name":"Test Package","Publisher":"Test Publisher","Description":"Test Description","Homepage":"https://test.com","License":"MIT","Tags":["test"]}}],"Total":1}'
    $Script:MockNotFoundResponse = '{"Packages":[],"Total":0}'
    $Script:MockPackageInfoResponse = '{"Packages":[{"Id":"7zip.7zip","Versions":["22.01","21.07"],"Latest":{"Name":"7-Zip","Publisher":"Igor Pavlov","Description":"File archiver","Homepage":"https://7-zip.org","License":"LGPL","Tags":["archiver","compression"]}}],"Total":1}'
    $Script:Mock64BitPackageResponse = '{"Packages":[{"Id":"Adobe.Acrobat.Reader.64-bit","Versions":["24.001"],"Latest":{"Name":"Adobe Acrobat Reader 64-bit","Publisher":"Adobe","Description":"PDF Reader","Homepage":"https://adobe.com","License":"Proprietary","Tags":["pdf","reader","64-bit"]}}],"Total":1}'
    $Script:MockNo64BitPackageResponse = '{"Packages":[{"Id":"SomeApp.App","Versions":["1.0"],"Latest":{"Name":"Some App","Publisher":"Some Publisher","Description":"An application","Homepage":"https://example.com","License":"MIT","Tags":["app"]}}],"Total":1}'
    
    # Mock responses for smart matching tests
    $Script:MockMultiplePackagesResponse = '{"Packages":[{"Id":"TTYPlus.MTPutty","Versions":["1.8"],"Latest":{"Name":"MTPuTTY","Publisher":"TTYPlus","Description":"Multi-Tabbed PuTTY","Homepage":"https://ttyplus.com","License":"Freeware","Tags":["ssh","terminal"]}},{"Id":"PuTTY.PuTTY","Versions":["0.80"],"Latest":{"Name":"PuTTY","Publisher":"Simon Tatham","Description":"SSH and telnet client","Homepage":"https://putty.org","License":"MIT","Tags":["ssh","telnet"]}},{"Id":"9XCODE.ExtraPuTTY","Versions":["1.0"],"Latest":{"Name":"ExtraPuTTY","Publisher":"9XCODE","Description":"Enhanced PuTTY","Homepage":"https://example.com","License":"MIT","Tags":["ssh"]}}],"Total":3}'
    $Script:MockPublisherMatchResponse = '{"Packages":[{"Id":"Test.WrongApp","Versions":["1.0"],"Latest":{"Name":"Test App","Publisher":"Wrong Publisher","Description":"Wrong app","Homepage":"https://wrong.com","License":"MIT","Tags":[]}},{"Id":"Test.CorrectApp","Versions":["1.0"],"Latest":{"Name":"Test App","Publisher":"Correct Publisher","Description":"Correct app","Homepage":"https://correct.com","License":"MIT","Tags":[]}}],"Total":2}'
}

AfterAll {
    # Clean up - remove the module after all tests
    Remove-Module WinGetLookup -Force -ErrorAction SilentlyContinue
}

Describe 'WinGetLookup Module' {
    Context 'Module Import' {
        It 'Should import the module without errors' {
            { Import-Module (Join-Path $PSScriptRoot 'WinGetLookup.psd1') -Force } | Should -Not -Throw
        }

        It 'Should export Test-WinGetPackage function' {
            Get-Command -Module WinGetLookup -Name 'Test-WinGetPackage' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-WinGetPackageInfo function' {
            Get-Command -Module WinGetLookup -Name 'Get-WinGetPackageInfo' | Should -Not -BeNullOrEmpty
        }

        It 'Should export exactly 7 functions' {
            (Get-Command -Module WinGetLookup).Count | Should -Be 7
        }

        It 'Should export Clear-WinGetCache function' {
            Get-Command -Module WinGetLookup -Name 'Clear-WinGetCache' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-WinGetCacheStatistics function' {
            Get-Command -Module WinGetLookup -Name 'Get-WinGetCacheStatistics' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-WinGet64BitAvailable function' {
            Get-Command -Module WinGetLookup -Name 'Test-WinGet64BitAvailable' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-WinGet64BitPackageId function' {
            Get-Command -Module WinGetLookup -Name 'Get-WinGet64BitPackageId' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Initialize-WinGetPackageCache function' {
            Get-Command -Module WinGetLookup -Name 'Initialize-WinGetPackageCache' | Should -Not -BeNullOrEmpty
        }

        It 'Should have a valid module manifest' {
            $manifest = Test-ModuleManifest -Path (Join-Path $PSScriptRoot 'WinGetLookup.psd1')
            $manifest | Should -Not -BeNullOrEmpty
        }

        It 'Should have version 1.7.0' {
            $manifest = Test-ModuleManifest -Path (Join-Path $PSScriptRoot 'WinGetLookup.psd1')
            $manifest.Version | Should -Be '1.7.0'
        }

        It 'Should have an author specified' {
            $manifest = Test-ModuleManifest -Path (Join-Path $PSScriptRoot 'WinGetLookup.psd1')
            $manifest.Author | Should -Not -BeNullOrEmpty
        }

        It 'Should have a description' {
            $manifest = Test-ModuleManifest -Path (Join-Path $PSScriptRoot 'WinGetLookup.psd1')
            $manifest.Description | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Cache Functions' {
    BeforeEach {
        # Clear cache before each test
        Clear-WinGetCache
    }

    Context 'Get-WinGetCacheStatistics' {
        It 'Should return a PSCustomObject' {
            $stats = Get-WinGetCacheStatistics
            $stats | Should -BeOfType [PSCustomObject]
        }

        It 'Should have CachedEntries property' {
            $stats = Get-WinGetCacheStatistics
            $stats.PSObject.Properties.Name | Should -Contain 'CachedEntries'
        }

        It 'Should have CacheHits property' {
            $stats = Get-WinGetCacheStatistics
            $stats.PSObject.Properties.Name | Should -Contain 'CacheHits'
        }

        It 'Should have CacheMisses property' {
            $stats = Get-WinGetCacheStatistics
            $stats.PSObject.Properties.Name | Should -Contain 'CacheMisses'
        }

        It 'Should have EfficiencyPct property' {
            $stats = Get-WinGetCacheStatistics
            $stats.PSObject.Properties.Name | Should -Contain 'EfficiencyPct'
        }

        It 'Should start with zero entries after clear' {
            $stats = Get-WinGetCacheStatistics
            $stats.CachedEntries | Should -Be 0
            $stats.CacheHits | Should -Be 0
            $stats.CacheMisses | Should -Be 0
        }
    }

    Context 'Clear-WinGetCache' {
        It 'Should not throw' {
            { Clear-WinGetCache } | Should -Not -Throw
        }

        It 'Should reset cache statistics' {
            # Make a mock call to populate cache
            Mock Invoke-RestMethod { return $Script:MockFoundResponse } -ModuleName WinGetLookup
            Test-WinGetPackage -DisplayName 'TestApp'
            
            # Verify cache has entry
            $statsBefore = Get-WinGetCacheStatistics
            $statsBefore.CacheMisses | Should -BeGreaterThan 0
            
            # Clear and verify
            Clear-WinGetCache
            $statsAfter = Get-WinGetCacheStatistics
            $statsAfter.CachedEntries | Should -Be 0
            $statsAfter.CacheHits | Should -Be 0
            $statsAfter.CacheMisses | Should -Be 0
        }
    }

    Context 'Caching Behavior' {
        It 'Should cache API response and use it on second call' {
            Mock Invoke-RestMethod { return $Script:MockFoundResponse } -ModuleName WinGetLookup
            
            # First call - should be cache miss
            Test-WinGetPackage -DisplayName 'TestApp'
            $stats1 = Get-WinGetCacheStatistics
            $stats1.CacheMisses | Should -Be 1
            $stats1.CacheHits | Should -Be 0
            
            # Second call with same term - should be cache hit
            Test-WinGetPackage -DisplayName 'TestApp'
            $stats2 = Get-WinGetCacheStatistics
            $stats2.CacheMisses | Should -Be 1
            $stats2.CacheHits | Should -Be 1
        }

        It 'Should have cache hit on case-insensitive search' {
            Mock Invoke-RestMethod { return $Script:MockFoundResponse } -ModuleName WinGetLookup
            
            Test-WinGetPackage -DisplayName 'TestApp'
            Test-WinGetPackage -DisplayName 'testapp'  # lowercase
            
            $stats = Get-WinGetCacheStatistics
            $stats.CacheHits | Should -Be 1
        }

        It 'Should calculate efficiency percentage correctly' {
            Mock Invoke-RestMethod { return $Script:MockFoundResponse } -ModuleName WinGetLookup
            
            # 1 miss, then 3 hits = 75% efficiency
            Test-WinGetPackage -DisplayName 'TestApp'
            Test-WinGetPackage -DisplayName 'TestApp'
            Test-WinGetPackage -DisplayName 'TestApp'
            Test-WinGetPackage -DisplayName 'TestApp'
            
            $stats = Get-WinGetCacheStatistics
            $stats.EfficiencyPct | Should -Be 75
        }
    }
}

Describe 'Test-WinGetPackage' {
    Context 'Parameter Validation' {
        It 'Should have mandatory DisplayName parameter' {
            $param = (Get-Command Test-WinGetPackage).Parameters['DisplayName']
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $mandatory.Mandatory | Should -Be $true
        }

        It 'Should accept DisplayName as positional parameter (position 0)' {
            $param = (Get-Command Test-WinGetPackage).Parameters['DisplayName']
            $posAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $posAttr.Position | Should -Be 0
        }

        It 'Should accept pipeline input for DisplayName' {
            $param = (Get-Command Test-WinGetPackage).Parameters['DisplayName']
            $pipeAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pipeAttr.ValueFromPipeline | Should -Be $true
        }

        It 'Should have Name alias for DisplayName' {
            $param = (Get-Command Test-WinGetPackage).Parameters['DisplayName']
            $param.Aliases | Should -Contain 'Name'
        }

        It 'Should have AppName alias for DisplayName' {
            $param = (Get-Command Test-WinGetPackage).Parameters['DisplayName']
            $param.Aliases | Should -Contain 'AppName'
        }

        It 'Should have ApplicationName alias for DisplayName' {
            $param = (Get-Command Test-WinGetPackage).Parameters['DisplayName']
            $param.Aliases | Should -Contain 'ApplicationName'
        }

        It 'Should have TimeoutSeconds parameter' {
            (Get-Command Test-WinGetPackage).Parameters['TimeoutSeconds'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Require64Bit parameter' {
            (Get-Command Test-WinGetPackage).Parameters['Require64Bit'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Require64Bit as switch parameter' {
            $param = (Get-Command Test-WinGetPackage).Parameters['Require64Bit']
            $param.ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have Publisher parameter' {
            (Get-Command Test-WinGetPackage).Parameters['Publisher'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Vendor alias for Publisher' {
            $param = (Get-Command Test-WinGetPackage).Parameters['Publisher']
            $param.Aliases | Should -Contain 'Vendor'
        }

        It 'Should have Author alias for Publisher' {
            $param = (Get-Command Test-WinGetPackage).Parameters['Publisher']
            $param.Aliases | Should -Contain 'Author'
        }

        It 'Should have PackageId parameter' {
            (Get-Command Test-WinGetPackage).Parameters['PackageId'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Id alias for PackageId' {
            $param = (Get-Command Test-WinGetPackage).Parameters['PackageId']
            $param.Aliases | Should -Contain 'Id'
        }

        It 'Should have WinGetId alias for PackageId' {
            $param = (Get-Command Test-WinGetPackage).Parameters['PackageId']
            $param.Aliases | Should -Contain 'WinGetId'
        }

        It 'Should validate TimeoutSeconds minimum range is 5' {
            $param = (Get-Command Test-WinGetPackage).Parameters['TimeoutSeconds']
            $validateRange = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $validateRange.MinRange | Should -Be 5
        }

        It 'Should validate TimeoutSeconds maximum range is 300' {
            $param = (Get-Command Test-WinGetPackage).Parameters['TimeoutSeconds']
            $validateRange = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $validateRange.MaxRange | Should -Be 300
        }

        It 'Should throw when DisplayName is null' {
            { Test-WinGetPackage -DisplayName $null } | Should -Throw
        }

        It 'Should throw when DisplayName is empty string' {
            { Test-WinGetPackage -DisplayName '' } | Should -Throw
        }

        It 'Should throw when TimeoutSeconds is below minimum (1)' {
            { Test-WinGetPackage -DisplayName 'Test' -TimeoutSeconds 1 } | Should -Throw
        }

        It 'Should throw when TimeoutSeconds is above maximum (500)' {
            { Test-WinGetPackage -DisplayName 'Test' -TimeoutSeconds 500 } | Should -Throw
        }
    }

    Context 'Return Values with Mocked API' {
        It 'Should return 1 when package is found' {
            Mock Invoke-RestMethod { return $Script:MockFoundResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'TestPackage'
            $result | Should -Be 1
        }

        It 'Should return 0 when package is not found' {
            Mock Invoke-RestMethod { return $Script:MockNotFoundResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'NonExistentPackage12345'
            $result | Should -Be 0
        }

        It 'Should return 0 when API throws an exception' {
            Clear-WinGetCache  # Ensure no cached data
            Mock Invoke-RestMethod { throw 'Network error' } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'UniqueFailTest12345' -WarningAction SilentlyContinue
            $result | Should -Be 0
        }

        It 'Should return integer type' {
            Mock Invoke-RestMethod { return $Script:MockFoundResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'TestPackage'
            $result | Should -BeOfType [int]
        }

        It 'Should only return 0 or 1' {
            Mock Invoke-RestMethod { return $Script:MockFoundResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'TestPackage'
            $result | Should -BeIn @(0, 1)
        }
    }

    Context 'Require64Bit Parameter with Mocked API' {
        It 'Should return 1 when package has 64-bit in ID' {
            Mock Invoke-RestMethod { return $Script:Mock64BitPackageResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'Adobe Acrobat Reader' -Require64Bit
            $result | Should -Be 1
        }

        It 'Should return 0 when package has no 64-bit indicators and -Require64Bit is specified' {
            Mock Invoke-RestMethod { return $Script:MockNo64BitPackageResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'SomeApp' -Require64Bit
            $result | Should -Be 0
        }

        It 'Should return 1 for known 64-bit package (7zip.7zip) with -Require64Bit' {
            Mock Invoke-RestMethod { return $Script:MockPackageInfoResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName '7-Zip' -Require64Bit
            $result | Should -Be 1
        }

        It 'Should return 1 without -Require64Bit even when package has no 64-bit indicators' {
            Mock Invoke-RestMethod { return $Script:MockNo64BitPackageResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'SomeApp'
            $result | Should -Be 1
        }

        It 'Should return 0 when package not found, regardless of -Require64Bit' {
            Mock Invoke-RestMethod { return $Script:MockNotFoundResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'NonExistent' -Require64Bit
            $result | Should -Be 0
        }

        It 'Should detect 64-bit from package name containing x64' {
            $mockX64Response = '{"Packages":[{"Id":"Test.App","Versions":["1.0"],"Latest":{"Name":"Test App x64","Publisher":"Test","Description":"Test","Homepage":"https://test.com","License":"MIT","Tags":["test"]}}],"Total":1}'
            Mock Invoke-RestMethod { return $mockX64Response } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'Test App' -Require64Bit
            $result | Should -Be 1
        }

        It 'Should detect 64-bit from tags containing 64-bit' {
            $mockTaggedResponse = '{"Packages":[{"Id":"Test.App","Versions":["1.0"],"Latest":{"Name":"Test App","Publisher":"Test","Description":"Test","Homepage":"https://test.com","License":"MIT","Tags":["test","64-bit"]}}],"Total":1}'
            Mock Invoke-RestMethod { return $mockTaggedResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'Test App' -Require64Bit
            $result | Should -Be 1
        }
    }

    Context 'Smart Matching with Mocked API' {
        It 'Should select PuTTY.PuTTY when searching for PuTTY (best match scoring)' {
            Mock Invoke-RestMethod { return $Script:MockMultiplePackagesResponse } -ModuleName WinGetLookup
            
            # The smart matching should pick PuTTY.PuTTY over MTPuTTY
            $result = Test-WinGetPackage -DisplayName 'PuTTY'
            $result | Should -Be 1
        }

        It 'Should return 1 when using -PackageId for exact match' {
            Mock Invoke-RestMethod { return $Script:MockMultiplePackagesResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'PuTTY' -PackageId 'PuTTY.PuTTY'
            $result | Should -Be 1
        }

        It 'Should return 0 when -PackageId does not match any package' {
            Mock Invoke-RestMethod { return $Script:MockMultiplePackagesResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'PuTTY' -PackageId 'NonExistent.Package'
            $result | Should -Be 0
        }

        It 'Should filter by publisher when -Publisher is specified' {
            Mock Invoke-RestMethod { return $Script:MockMultiplePackagesResponse } -ModuleName WinGetLookup
            
            $result = Test-WinGetPackage -DisplayName 'PuTTY' -Publisher 'Simon Tatham'
            $result | Should -Be 1
        }

        It 'Should prefer publisher match over other matches' {
            Mock Invoke-RestMethod { return $Script:MockPublisherMatchResponse } -ModuleName WinGetLookup
            
            # Without publisher filter, first match might be wrong
            # With publisher filter, should find correct one
            $result = Test-WinGetPackage -DisplayName 'Test App' -Publisher 'Correct Publisher'
            $result | Should -Be 1
        }
    }

    Context 'URL Encoding' {
        It 'Should call API when DisplayName contains special characters' {
            Mock Invoke-RestMethod { return $Script:MockNotFoundResponse } -ModuleName WinGetLookup
            
            Test-WinGetPackage -DisplayName 'Notepad++'
            Should -Invoke Invoke-RestMethod -ModuleName WinGetLookup -Times 1
        }
    }

    Context 'Pipeline Support' {
        BeforeEach {
            Mock Invoke-RestMethod { return $Script:MockFoundResponse } -ModuleName WinGetLookup
        }

        It 'Should accept pipeline input' {
            $result = 'TestApp' | Test-WinGetPackage
            $result | Should -Be 1
        }

        It 'Should process multiple pipeline inputs' {
            $results = @('App1', 'App2', 'App3') | ForEach-Object { Test-WinGetPackage $_ }
            $results.Count | Should -Be 3
        }

        It 'Should return correct count for each input' {
            $results = @('App1', 'App2') | ForEach-Object { Test-WinGetPackage $_ }
            $results | Should -HaveCount 2
        }
    }

    Context 'Verbose Output' {
        It 'Should produce verbose output when -Verbose is specified' {
            Mock Invoke-RestMethod { return $Script:MockNotFoundResponse } -ModuleName WinGetLookup
            
            $verboseOutput = Test-WinGetPackage -DisplayName 'TestApp' -Verbose 4>&1
            $verboseOutput | Should -Not -BeNullOrEmpty
        }

        It 'Should include package name in verbose output' {
            Mock Invoke-RestMethod { return $Script:MockNotFoundResponse } -ModuleName WinGetLookup
            
            $verboseOutput = Test-WinGetPackage -DisplayName 'MyTestApp' -Verbose 4>&1
            ($verboseOutput | Out-String) | Should -Match 'MyTestApp'
        }
    }
}

Describe 'Get-WinGetPackageInfo' {
    Context 'Parameter Validation' {
        It 'Should have mandatory DisplayName parameter' {
            $param = (Get-Command Get-WinGetPackageInfo).Parameters['DisplayName']
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $mandatory.Mandatory | Should -Be $true
        }

        It 'Should accept DisplayName as positional parameter (position 0)' {
            $param = (Get-Command Get-WinGetPackageInfo).Parameters['DisplayName']
            $posAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $posAttr.Position | Should -Be 0
        }

        It 'Should accept pipeline input for DisplayName' {
            $param = (Get-Command Get-WinGetPackageInfo).Parameters['DisplayName']
            $pipeAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pipeAttr.ValueFromPipeline | Should -Be $true
        }

        It 'Should have TimeoutSeconds parameter' {
            (Get-Command Get-WinGetPackageInfo).Parameters['TimeoutSeconds'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Publisher parameter' {
            (Get-Command Get-WinGetPackageInfo).Parameters['Publisher'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have PackageId parameter' {
            (Get-Command Get-WinGetPackageInfo).Parameters['PackageId'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Return Values with Mocked API' {
        It 'Should return PSCustomObject when package is found' {
            Mock Invoke-RestMethod { return $Script:MockPackageInfoResponse } -ModuleName WinGetLookup
            
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result | Should -BeOfType [PSCustomObject]
        }

        It 'Should return object with Found=True when package exists' {
            Mock Invoke-RestMethod { return $Script:MockPackageInfoResponse } -ModuleName WinGetLookup
            
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.Found | Should -Be $true
        }

        It 'Should return object with Id when package exists' {
            Mock Invoke-RestMethod { return $Script:MockPackageInfoResponse } -ModuleName WinGetLookup
            
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.Id | Should -Not -BeNullOrEmpty
        }

        It 'Should return object with Name when package exists' {
            Mock Invoke-RestMethod { return $Script:MockPackageInfoResponse } -ModuleName WinGetLookup
            
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.Name | Should -Not -BeNullOrEmpty
        }

        It 'Should return object with Found=False when package not found' {
            Mock Invoke-RestMethod { return $Script:MockNotFoundResponse } -ModuleName WinGetLookup
            
            $result = Get-WinGetPackageInfo -DisplayName 'NonExistentApp'
            $result.Found | Should -Be $false
        }

        It 'Should return Found=False when API throws an exception' {
            Clear-WinGetCache  # Ensure no cached data
            Mock Invoke-RestMethod { throw 'Network error' } -ModuleName WinGetLookup
            
            $result = Get-WinGetPackageInfo -DisplayName 'UniqueFailTest67890' -WarningAction SilentlyContinue
            $result.Found | Should -Be $false
        }
    }

    Context 'Return Object Properties' {
        BeforeEach {
            Mock Invoke-RestMethod { return $Script:MockPackageInfoResponse } -ModuleName WinGetLookup
        }

        It 'Should have Id property' {
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.PSObject.Properties.Name | Should -Contain 'Id'
        }

        It 'Should have Name property' {
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.PSObject.Properties.Name | Should -Contain 'Name'
        }

        It 'Should have Publisher property' {
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.PSObject.Properties.Name | Should -Contain 'Publisher'
        }

        It 'Should have Description property' {
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.PSObject.Properties.Name | Should -Contain 'Description'
        }

        It 'Should have Homepage property' {
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.PSObject.Properties.Name | Should -Contain 'Homepage'
        }

        It 'Should have License property' {
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.PSObject.Properties.Name | Should -Contain 'License'
        }

        It 'Should have Found property' {
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.PSObject.Properties.Name | Should -Contain 'Found'
        }

        It 'Should have Has64BitIndicator property' {
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.PSObject.Properties.Name | Should -Contain 'Has64BitIndicator'
        }

        It 'Has64BitIndicator should be boolean' {
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.Has64BitIndicator | Should -BeOfType [bool]
        }
    }
}

Describe 'Test-WinGet64BitAvailable' {
    Context 'Parameter Validation' {
        It 'Should have PackageId as mandatory parameter' {
            $param = (Get-Command Test-WinGet64BitAvailable).Parameters['PackageId']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Be $true
        }

        It 'Should accept pipeline input for PackageId' {
            $param = (Get-Command Test-WinGet64BitAvailable).Parameters['PackageId']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).ValueFromPipeline | Should -Be $true
        }

        It 'Should have TimeoutSeconds parameter' {
            (Get-Command Test-WinGet64BitAvailable).Parameters['TimeoutSeconds'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Id alias for PackageId' {
            $param = (Get-Command Test-WinGet64BitAvailable).Parameters['PackageId']
            $param.Aliases | Should -Contain 'Id'
        }
    }

    Context 'CLI-based 64-bit Detection' -Tag 'Integration' {
        It 'Should return true for known 64-bit package (7zip.7zip)' {
            $result = Test-WinGet64BitAvailable -PackageId '7zip.7zip'
            $result | Should -Be $true
        }

        It 'Should return true for WinRAR (CLI verification catches what heuristics miss)' {
            $result = Test-WinGet64BitAvailable -PackageId 'RARLab.WinRAR'
            $result | Should -Be $true
        }

        It 'Should return false for 32-bit only package' {
            $result = Test-WinGet64BitAvailable -PackageId 'Adobe.Acrobat.Reader.32-bit'
            $result | Should -Be $false
        }

        It 'Should return false for non-existent package' {
            $result = Test-WinGet64BitAvailable -PackageId 'NonExistent.FakePackage.12345'
            $result | Should -Be $false
        }

        It 'Should return boolean type' {
            $result = Test-WinGet64BitAvailable -PackageId '7zip.7zip'
            $result | Should -BeOfType [bool]
        }
    }
}

Describe 'Get-WinGet64BitPackageId' {
    Context 'Parameter Validation' {
        It 'Should have PackageId as mandatory parameter' {
            $param = (Get-Command Get-WinGet64BitPackageId).Parameters['PackageId']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Be $true
        }

        It 'Should accept pipeline input for PackageId' {
            $param = (Get-Command Get-WinGet64BitPackageId).Parameters['PackageId']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).ValueFromPipeline | Should -Be $true
        }

        It 'Should have Id alias for PackageId' {
            $param = (Get-Command Get-WinGet64BitPackageId).Parameters['PackageId']
            $param.Aliases | Should -Contain 'Id'
        }
    }

    Context 'Separate 64-bit Package Detection' -Tag 'Integration' {
        It 'Should return 64-bit variant for Adobe.Acrobat.Reader.32-bit' {
            $result = Get-WinGet64BitPackageId -PackageId 'Adobe.Acrobat.Reader.32-bit'
            $result | Should -Be 'Adobe.Acrobat.Reader.64-bit'
        }

        It 'Should return same ID for packages with x64 installer (7zip)' {
            $result = Get-WinGet64BitPackageId -PackageId '7zip.7zip'
            $result | Should -Be '7zip.7zip'
        }

        It 'Should return same ID for packages with x64 installer (WinRAR)' {
            $result = Get-WinGet64BitPackageId -PackageId 'RARLab.WinRAR'
            $result | Should -Be 'RARLab.WinRAR'
        }

        It 'Should return null for non-existent package' {
            $result = Get-WinGet64BitPackageId -PackageId 'NonExistent.FakePackage.12345'
            $result | Should -BeNullOrEmpty
        }

        It 'Should return string type for valid package' {
            $result = Get-WinGet64BitPackageId -PackageId '7zip.7zip'
            $result | Should -BeOfType [string]
        }
    }
}

Describe 'Help Documentation' {
    Context 'Test-WinGetPackage Help' {
        BeforeAll {
            $script:help = Get-Help Test-WinGetPackage -Full
        }

        It 'Should have a synopsis' {
            $script:help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'Should have a description' {
            $script:help.Description | Should -Not -BeNullOrEmpty
        }

        It 'Should have parameter documentation for DisplayName' {
            $paramHelp = $script:help.Parameters.Parameter | Where-Object { $_.Name -eq 'DisplayName' }
            $paramHelp.Description | Should -Not -BeNullOrEmpty
        }

        It 'Should have parameter documentation for TimeoutSeconds' {
            $paramHelp = $script:help.Parameters.Parameter | Where-Object { $_.Name -eq 'TimeoutSeconds' }
            $paramHelp.Description | Should -Not -BeNullOrEmpty
        }

        It 'Should have at least 2 examples' {
            $script:help.Examples.Example.Count | Should -BeGreaterOrEqual 2
        }

        It 'Should have notes section' {
            $script:help.alertSet | Should -Not -BeNullOrEmpty
        }

        It 'Should have related links' {
            $script:help.relatedLinks | Should -Not -BeNullOrEmpty
        }

        It 'Should document output type' {
            $script:help.returnValues | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-WinGetPackageInfo Help' {
        BeforeAll {
            $script:help = Get-Help Get-WinGetPackageInfo -Full
        }

        It 'Should have a synopsis' {
            $script:help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'Should have a description' {
            $script:help.Description | Should -Not -BeNullOrEmpty
        }

        It 'Should have examples' {
            $script:help.Examples.Example | Should -Not -BeNullOrEmpty
        }

        It 'Should have parameter documentation for DisplayName' {
            $paramHelp = $script:help.Parameters.Parameter | Where-Object { $_.Name -eq 'DisplayName' }
            $paramHelp.Description | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Integration Tests' -Tag 'Integration' {
    # These tests require internet connectivity and hit the live API
    # Run with: Invoke-Pester -Path .\WinGetLookup.Tests.ps1 -Tag 'Integration'
    
    Context 'Live API - Test-WinGetPackage' {
        It 'Should find Notepad++ in WinGet repository' {
            $result = Test-WinGetPackage -DisplayName 'Notepad++'
            $result | Should -Be 1
        }

        It 'Should find 7-Zip in WinGet repository' {
            $result = Test-WinGetPackage -DisplayName '7-Zip'
            $result | Should -Be 1
        }

        It 'Should find VLC in WinGet repository' {
            $result = Test-WinGetPackage -DisplayName 'VLC'
            $result | Should -Be 1
        }

        It 'Should not find a non-existent package' {
            $result = Test-WinGetPackage -DisplayName 'ThisPackageDefinitelyDoesNotExist123456789xyz'
            $result | Should -Be 0
        }

        It 'Should work with -Name alias' {
            $result = Test-WinGetPackage -Name 'Firefox'
            $result | Should -Be 1
        }
    }

    Context 'Live API - Get-WinGetPackageInfo' {
        It 'Should return detailed info for 7-Zip' {
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip'
            $result.Found | Should -Be $true
            $result.Id | Should -Match '7zip'
            $result.Publisher | Should -Not -BeNullOrEmpty
        }

        It 'Should return detailed info for VLC' {
            $result = Get-WinGetPackageInfo -DisplayName 'VLC'
            $result.Found | Should -Be $true
            $result.Name | Should -Match 'VLC'
        }

        It 'Should return Found=False for non-existent package' {
            $result = Get-WinGetPackageInfo -DisplayName 'NonExistentApp987654321'
            $result.Found | Should -Be $false
        }
    }

    Context 'Live API - Require64Bit Tests' {
        It 'Should return 1 for 7-Zip with -Require64Bit (known 64-bit package)' {
            $result = Test-WinGetPackage -DisplayName '7-Zip' -Require64Bit
            $result | Should -Be 1
        }

        It 'Should return 1 for Notepad++ with -Require64Bit (known 64-bit package)' {
            $result = Test-WinGetPackage -DisplayName 'Notepad++' -Require64Bit
            $result | Should -Be 1
        }

        It 'Should return 1 for VLC with -Require64Bit (known 64-bit package)' {
            $result = Test-WinGetPackage -DisplayName 'VLC' -Require64Bit
            $result | Should -Be 1
        }

        It 'Should return 0 for non-existent package with -Require64Bit' {
            $result = Test-WinGetPackage -DisplayName 'ThisPackageDefinitelyDoesNotExist123456789xyz' -Require64Bit
            $result | Should -Be 0
        }

        It 'Should return 1 for Visual Studio Code with -Require64Bit (known 64-bit package)' {
            $result = Test-WinGetPackage -DisplayName 'Visual Studio Code' -Require64Bit
            $result | Should -Be 1
        }

        It 'Should return 1 for Git with -Require64Bit (known 64-bit package)' {
            $result = Test-WinGetPackage -DisplayName 'Git' -Require64Bit
            $result | Should -Be 1
        }

        It 'Should return 1 for WinSCP with -Require64Bit (known 64-bit package)' {
            $result = Test-WinGetPackage -DisplayName 'WinSCP' -Require64Bit
            $result | Should -Be 1
        }

        It 'Should return 1 for Bitwarden with -Require64Bit (known 64-bit package)' {
            $result = Test-WinGetPackage -DisplayName 'Bitwarden' -Require64Bit
            $result | Should -Be 1
        }
    }

    Context 'Live API - Smart Matching Tests' {
        It 'Should find PuTTY.PuTTY when searching for PuTTY (not MTPuTTY)' {
            $result = Get-WinGetPackageInfo -DisplayName 'PuTTY'
            $result.Found | Should -Be $true
            $result.Id | Should -Be 'PuTTY.PuTTY'
        }

        It 'Should find PuTTY by Simon Tatham when using -Publisher' {
            $result = Get-WinGetPackageInfo -DisplayName 'PuTTY' -Publisher 'Simon Tatham'
            $result.Found | Should -Be $true
            $result.Id | Should -Be 'PuTTY.PuTTY'
            $result.Publisher | Should -Match 'Simon Tatham'
        }

        It 'Should find exact package when using -PackageId' {
            $result = Get-WinGetPackageInfo -DisplayName 'PuTTY' -PackageId 'PuTTY.PuTTY'
            $result.Found | Should -Be $true
            $result.Id | Should -Be 'PuTTY.PuTTY'
        }

        It 'Should return Found=False when -PackageId does not match' {
            $result = Get-WinGetPackageInfo -DisplayName 'PuTTY' -PackageId 'NonExistent.Package'
            $result.Found | Should -Be $false
        }

        It 'Should find 7-Zip by Igor Pavlov when using -Publisher' {
            $result = Get-WinGetPackageInfo -DisplayName '7-Zip' -Publisher 'Igor Pavlov'
            $result.Found | Should -Be $true
            $result.Id | Should -Match '7zip'
        }

        It 'Should work with Test-WinGetPackage and -Publisher' {
            $result = Test-WinGetPackage -DisplayName 'PuTTY' -Publisher 'Simon Tatham'
            $result | Should -Be 1
        }

        It 'Should work with Test-WinGetPackage and -PackageId' {
            $result = Test-WinGetPackage -DisplayName 'PuTTY' -PackageId 'PuTTY.PuTTY'
            $result | Should -Be 1
        }
    }
}
