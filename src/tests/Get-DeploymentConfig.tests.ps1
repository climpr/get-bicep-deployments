BeforeAll {
    Import-Module $PSScriptRoot/../support-functions.psm1 -Force
}

Describe "Get-DeploymentConfig" {
    BeforeAll {
        # Create test directory structure in TestDrive
        $script:testRoot = Join-Path $TestDrive 'test'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        
        # Create default config
        $defaultConfig = @{
            name            = "default-name"
            azureCliVersion = "2.68.0"
            location        = "westeurope"
        } | ConvertTo-Json
        $script:defaultConfigPath = Join-Path $testRoot "default.deploymentconfig.json"
        Set-Content -Path $defaultConfigPath -Value $defaultConfig

        # Common parameters for all tests
        $script:commonParam = @{
            DefaultDeploymentConfigPath = $defaultConfigPath
        }
    }

    Context "Deployment config file formats" {
        BeforeEach {
            $script:deploymentPath = Join-Path $testRoot ([System.IO.Path]::GetRandomFileName())
            New-Item -Path $deploymentPath -ItemType Directory -Force | Out-Null
        }

        It "Should read JSON config file" {
            $config = @{
                name     = "deployment-name"
                location = "northeurope"
            } | ConvertTo-Json
            Set-Content -Path (Join-Path $deploymentPath "deploymentconfig.json") -Value $config

            $params = @{
                DeploymentDirectoryPath = $deploymentPath
                DeploymentFileName      = "dev.bicepparam"
            }

            $result = Get-DeploymentConfig @commonParam @params
            $result.name | Should -Be "deployment-name"
        }

        It "Should read JSONC config file" {
            $config = @"
{
    // This is a JSONC file
    "name": "deployment-name",
    "location": "northeurope" // With comments
}
"@
            Set-Content -Path (Join-Path $deploymentPath "deploymentconfig.jsonc") -Value $config

            $params = @{
                DeploymentDirectoryPath = $deploymentPath
                DeploymentFileName      = "dev.bicepparam"
            }

            $result = Get-DeploymentConfig @commonParam @params
            $result.name | Should -Be "deployment-name"
        }

        It "Should throw on multiple config files" {
            Set-Content -Path (Join-Path $deploymentPath "deploymentconfig.json") -Value "{}"
            Set-Content -Path (Join-Path $deploymentPath "deploymentconfig.jsonc") -Value "{}"

            $params = @{
                DeploymentDirectoryPath = $deploymentPath
                DeploymentFileName      = "dev.bicepparam"
            }

            { Get-DeploymentConfig @commonParam @params } | 
            Should -Throw "*Found multiple deploymentconfig files.*"
        }
    }

    Context "Config value precedence" {
        BeforeEach {
            $script:deploymentPath = Join-Path $testRoot ([System.IO.Path]::GetRandomFileName())
            New-Item -Path $deploymentPath -ItemType Directory -Force | Out-Null
        }

        It "Should override default values with local config" {
            $config = @{
                name     = "deployment-name"
                location = "northeurope"
            } | ConvertTo-Json
            Set-Content -Path (Join-Path $deploymentPath "deploymentconfig.json") -Value $config

            $params = @{
                DeploymentDirectoryPath = $deploymentPath
                DeploymentFileName      = "dev.bicepparam"
            }

            $result = Get-DeploymentConfig @commonParam @params
            $result.location | Should -Be "northeurope"
            $result.name | Should -Be "deployment-name"
        }

        It "Should fall back to default values when not in local config" {
            $config = @{
                name = "deployment-name"
            } | ConvertTo-Json
            Set-Content -Path (Join-Path $deploymentPath "deploymentconfig.json") -Value $config

            $params = @{
                DeploymentDirectoryPath = $deploymentPath
                DeploymentFileName      = "dev.bicepparam"
            }

            $result = Get-DeploymentConfig @commonParam @params
            $result.azureCliVersion | Should -Be "2.68.0"
        }
    }

    AfterAll {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
