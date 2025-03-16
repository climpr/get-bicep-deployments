@{ SuiteName = 'Get-ClimprConfig Tests' }

BeforeAll {
    Import-Module $PSScriptRoot/../support-functions.psm1 -Force
}

Describe "Get-ClimprConfig" {
    BeforeAll {
        $tempDir = $env:TEMP ?? $env:TMPDIR ?? "/tmp"
        $testRoot = Join-Path $tempDir "ClimprConfigTest"
        $subDir = Join-Path $testRoot "SubDir"
        
        # Ensure clean environment
        Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue
        
        # Create test directories
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $subDir -Force | Out-Null

        # Create test config files
        $config1 = @{ SettingA = "Value1" } | ConvertTo-Json -Depth 10
        $config2 = @{ SettingB = "Value2" } | ConvertTo-Json -Depth 10
        Set-Content -Path (Join-Path $testRoot "climprconfig.json") -Value $config1
        Set-Content -Path (Join-Path $subDir "climprconfig.jsonc") -Value $config2
    }

    AfterAll {
        Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue
    }

    It "Should return an empty hashtable if no config files exist" {
        $emptyDir = Join-Path $tempDir "EmptyDir"
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        
        $result = Get-ClimprConfig -DeploymentDirectoryPath $emptyDir
        
        Remove-Item -Recurse -Force $emptyDir -ErrorAction SilentlyContinue
        $result | Should -BeOfType Hashtable
        $result.Keys.Count | Should -Be 0
    }

    It "Should find and merge configurations from multiple directories" {
        $result = Get-ClimprConfig -DeploymentDirectoryPath $subDir
        
        $result | Should -BeOfType Hashtable
        $result.Keys | Should -Contain "SettingA"
        $result.Keys | Should -Contain "SettingB"
        $result["SettingA"] | Should -Be "Value1"
        $result["SettingB"] | Should -Be "Value2"
    }

    It "Should prioritize jsonc over json when both exist" {
        $subDirConfig = @{ SettingA = "OverriddenValue" } | ConvertTo-Json -Depth 10
        Set-Content -Path (Join-Path $subDir "climprconfig.jsonc") -Value $subDirConfig

        $result = Get-ClimprConfig -DeploymentDirectoryPath $subDir
        
        $result["SettingA"] | Should -Be "OverriddenValue"
    }

    It "Should fail on non-existent directory" {
        $nonExistentDir = Join-Path $tempDir "DoesNotExist"
        { Get-ClimprConfig -DeploymentDirectoryPath $nonExistentDir } | Should -Throw
    }

    It "Should handle malformed JSON gracefully" {
        $malformedJsonPath = Join-Path $subDir "climprconfig.json"
        Set-Content -Path $malformedJsonPath -Value "{ invalid json }"
        
        { Get-ClimprConfig -DeploymentDirectoryPath $subDir } | Should -Not -Throw
    }
}
