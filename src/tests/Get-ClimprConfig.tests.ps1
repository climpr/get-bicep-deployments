BeforeAll {
    Import-Module $PSScriptRoot/../DeployBicepHelpers.psm1 -Force

    function New-FileStructure {
        param (
            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [hashtable] $Structure
        )
        
        if (!(Test-Path -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
    
        foreach ($key in $Structure.Keys) {
            $itemPath = Join-Path -Path $Path -ChildPath $key
            if ($Structure[$key] -is [hashtable]) {
                New-FileStructure -Path $itemPath -Structure $Structure[$key]
            }
            else {
                Set-Content -Path $itemPath -Value $Structure[$key] -Force
            }
        }
    }
}

Describe "Get-ClimprConfig" {
    BeforeEach {
        # Create mock root directory
        $script:testRoot = Join-Path $TestDrive 'mock'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue -ProgressAction SilentlyContinue
    }

    Context "Basic configuration handling" {
        It "Should find configuration with .json extension" {
            New-FileStructure -Path $testRoot -Structure @{
                "climprconfig.json" = @{ setting = "value" } | ConvertTo-Json
            }
            Get-ClimprConfig -DeploymentDirectoryPath $testRoot | Select-Object -ExpandProperty "setting" | Should -BeExactly "value"
        }

        It "Should find configuration with .jsonc extension" {
            New-FileStructure -Path $testRoot -Structure @{
                "climprconfig.jsonc" = @{ setting = "value" } | ConvertTo-Json
            }
            Get-ClimprConfig -DeploymentDirectoryPath $testRoot | Select-Object -ExpandProperty "setting" | Should -BeExactly "value"
        }

        It "Should return an empty hashtable if no config files exist" {
            $result = Get-ClimprConfig -DeploymentDirectoryPath $testRoot
            
            $result | Should -BeOfType Hashtable
            $result.Keys.Count | Should -BeExactly 0
        }

        It "Should find configuration from current directory" {
            New-FileStructure -Path $testRoot -Structure @{
                "climprconfig.jsonc" = @{ setting = "value" } | ConvertTo-Json
            }
            Get-ClimprConfig -DeploymentDirectoryPath $testRoot | Select-Object -ExpandProperty "setting" | Should -BeExactly "value"
        }

        It "Should find configuration from parent directory" {
            New-FileStructure -Path $testRoot -Structure @{
                "climprconfig.jsonc" = @{ setting = "value" } | ConvertTo-Json
                "subdir"             = @{}
            }
            Get-ClimprConfig -DeploymentDirectoryPath "$testRoot/subdir" | Select-Object -ExpandProperty "setting" | Should -BeExactly "value"
        }

        It "Should merge configurations from current and parent directories" {
            New-FileStructure -Path $testRoot -Structure @{
                "climprconfig.jsonc" = @{ SettingA = "Value1" } | ConvertTo-Json
                "subdir"             = @{
                    "climprconfig.jsonc" = @{ SettingB = "Value2" } | ConvertTo-Json
                }
            }
            $result = Get-ClimprConfig -DeploymentDirectoryPath "$testRoot/subdir"
            
            $result.Keys | Should -Contain "SettingA"
            $result.Keys | Should -Contain "SettingB"
            $result["SettingA"] | Should -BeExactly "Value1"
            $result["SettingB"] | Should -BeExactly "Value2"
        }
    }

    Context "Configuration precedence" {
        It "Should prioritize jsonc over json when both exist" {
            New-FileStructure -Path $testRoot -Structure @{
                "climprconfig.json"  = @{ setting = "value" } | ConvertTo-Json
                "climprconfig.jsonc" = @{ setting = "overridden" } | ConvertTo-Json
            }
            Get-ClimprConfig -DeploymentDirectoryPath $testRoot | Select-Object -ExpandProperty "setting" | Should -BeExactly "overridden"
        }

        It "Should prioritize child directory config over parent" {
            New-FileStructure -Path $testRoot -Structure @{
                "climprconfig.jsonc" = @{ setting = "parentvalue" } | ConvertTo-Json
                "subdir"             = @{
                    "climprconfig.jsonc" = @{ setting = "childvalue" } | ConvertTo-Json
                }
            }
            Get-ClimprConfig -DeploymentDirectoryPath "$testRoot/subdir" | Select-Object -ExpandProperty "setting" | Should -BeExactly "childvalue"
        }
    }

    Context "Error handling" {
        It "Should fail on non-existent directory" {
            $nonExistentDir = Join-Path $testRoot "DoesNotExist"
            { Get-ClimprConfig -DeploymentDirectoryPath $nonExistentDir } | 
            Should -Throw "Cannot validate argument on parameter 'DeploymentDirectoryPath'*"
        }

        It "Should handle malformed JSON gracefully" {
            New-FileStructure -Path $testRoot -Structure @{
                "climprconfig.jsonc" = "{ invalid json }"
            }
            { Get-ClimprConfig -DeploymentDirectoryPath $testRoot -WarningAction Ignore } | Should -Not -Throw
        }
    }
}
