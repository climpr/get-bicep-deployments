@{ SuiteName = 'Get-ClimprConfig Tests' }

BeforeAll {
    Import-Module $PSScriptRoot/../support-functions.psm1 -Force
}

Describe "Get-ClimprConfig" {
    BeforeAll {
        $script:testRoot = Join-Path $TestDrive 'ClimprConfigTest'
        $script:subDir = Join-Path $testRoot 'SubDir'
        
        # Create test directories
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $subDir -Force | Out-Null
    }

    Context "Basic configuration handling" {
        BeforeEach {
            # Create test config files
            $config1 = @{ SettingA = "Value1" } | ConvertTo-Json -Depth 10
            $config2 = @{ SettingB = "Value2" } | ConvertTo-Json -Depth 10
            Set-Content -Path (Join-Path $testRoot "climprconfig.json") -Value $config1
            Set-Content -Path (Join-Path $subDir "climprconfig.jsonc") -Value $config2
        }

        It "Should find and merge configurations from multiple directories" {
            $result = Get-ClimprConfig -DeploymentDirectoryPath $subDir
            
            $result | Should -BeOfType Hashtable
            $result.Keys | Should -Contain "SettingA"
            $result.Keys | Should -Contain "SettingB"
            $result["SettingA"] | Should -Be "Value1"
            $result["SettingB"] | Should -Be "Value2"
        }

        It "Should return an empty hashtable if no config files exist" {
            $emptyDir = Join-Path $TestDrive "EmptyDir"
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
            
            $result = Get-ClimprConfig -DeploymentDirectoryPath $emptyDir
            
            $result | Should -BeOfType Hashtable
            $result.Keys.Count | Should -Be 0
        }
    }

    Context "Configuration precedence" {
        It "Should prioritize jsonc over json when both exist" {
            $config1 = @{ SettingA = "Value1" } | ConvertTo-Json -Depth 10
            $config2 = @{ SettingA = "OverriddenValue" } | ConvertTo-Json -Depth 10
            
            Set-Content -Path (Join-Path $subDir "climprconfig.json") -Value $config1
            Set-Content -Path (Join-Path $subDir "climprconfig.jsonc") -Value $config2

            $result = Get-ClimprConfig -DeploymentDirectoryPath $subDir
            $result["SettingA"] | Should -Be "OverriddenValue"
        }

        It "Should prioritize child directory config over parent" {
            $parentConfig = @{ SettingA = "ParentValue" } | ConvertTo-Json -Depth 10
            $childConfig = @{ SettingA = "ChildValue" } | ConvertTo-Json -Depth 10
            
            Set-Content -Path (Join-Path $testRoot "climprconfig.json") -Value $parentConfig
            Set-Content -Path (Join-Path $subDir "climprconfig.json") -Value $childConfig

            $result = Get-ClimprConfig -DeploymentDirectoryPath $subDir
            $result["SettingA"] | Should -Be "ChildValue"
        }
    }

    Context "Error handling" {
        It "Should fail on non-existent directory" {
            $nonExistentDir = Join-Path $TestDrive "DoesNotExist"
            { Get-ClimprConfig -DeploymentDirectoryPath $nonExistentDir } | 
            Should -Throw "Cannot validate argument on parameter 'DeploymentDirectoryPath'*"
        }

        It "Should handle malformed JSON gracefully" {
            Set-Content -Path (Join-Path $subDir "climprconfig.json") -Value "{ invalid json }"
            
            { Get-ClimprConfig -DeploymentDirectoryPath $subDir } | Should -Not -Throw
        }
    }

    AfterEach {
        Get-ChildItem -Path $testRoot -Filter "climprconfig.*" -Recurse | Remove-Item -Force
    }

    AfterAll {
        Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue
    }
}
