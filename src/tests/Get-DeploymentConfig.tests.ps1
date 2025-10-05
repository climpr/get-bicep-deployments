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

Describe "Get-DeploymentConfig" {
    BeforeEach {
        # Create mock root directory
        $script:testRoot = Join-Path $TestDrive 'mock'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

        # Create default config
        New-FileStructure -Path $testRoot -Structure @{
            'default.deploymentconfig.jsonc' = @{
                name            = "default-name"
                azureCliVersion = "latest"
                bicepVersion    = "latest"
                location        = "westeurope"
            } | ConvertTo-Json
        }

        # Common parameters for all tests
        $script:commonParam = @{
            DefaultDeploymentConfigPath = "$testRoot/default.deploymentconfig.jsonc"
        }
    }

    AfterEach {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue -ProgressAction SilentlyContinue
    }
    
    Context "Deployment config file formats" {
        It "Should read JSON config file" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'            = "targetScope = 'subscription'"
                'prod.bicepparam'       = "using 'main.bicep"
                'deploymentconfig.json' = @{ name = "mock-name" } | ConvertTo-Json
            }

            $result = Get-DeploymentConfig @commonParam -DeploymentDirectoryPath $testRoot -DeploymentFileName "prod.bicepparam"
            $result.name | Should -BeExactly "mock-name"
        }

        It "Should read JSONC config file" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'             = "targetScope = 'subscription'"
                'prod.bicepparam'        = "using 'main.bicep"
                'deploymentconfig.jsonc' = @"
{
    // This is a JSONC file
    "name": "mock-name",
    "location": "northeurope" // With comments
}
"@
            }

            $result = Get-DeploymentConfig @commonParam -DeploymentDirectoryPath $testRoot -DeploymentFileName "prod.bicepparam"
            $result.name | Should -BeExactly "mock-name"
        }

        It "Should throw on multiple config files" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'             = "targetScope = 'subscription'"
                'prod.bicepparam'        = "using 'main.bicep"
                'deploymentconfig.json'  = "{}"
                'deploymentconfig.jsonc' = "{}"
            }

            { Get-DeploymentConfig @commonParam -DeploymentDirectoryPath $testRoot -DeploymentFileName "prod.bicepparam" } | 
            Should -Throw "*Found multiple deploymentconfig files.*"
        }
    }

    Context "Config value precedence" {
        It "Should override default values with local config" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'             = "targetScope = 'subscription'"
                'prod.bicepparam'        = "using 'main.bicep"
                'deploymentconfig.jsonc' = @{
                    name     = "mock-name"
                    location = "northeurope"
                } | ConvertTo-Json
            }

            $result = Get-DeploymentConfig @commonParam -DeploymentDirectoryPath $testRoot -DeploymentFileName "prod.bicepparam"
            $result.name | Should -BeExactly "mock-name"
            $result.location | Should -BeExactly "northeurope"
        }

        It "Should fall back to default values when not in local config" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'             = "targetScope = 'subscription'"
                'prod.bicepparam'        = "using 'main.bicep"
                'deploymentconfig.jsonc' = @{
                    name = "mock-name"
                } | ConvertTo-Json
            }

            $result = Get-DeploymentConfig @commonParam -DeploymentDirectoryPath $testRoot -DeploymentFileName "prod.bicepparam"
            $result.name | Should -BeExactly "mock-name"
            $result.location | Should -BeExactly "westeurope"
        }
    }
}
