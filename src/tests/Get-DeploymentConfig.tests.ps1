BeforeAll {
    Import-Module $PSScriptRoot/../support-functions.psm1 -Force
    $script:mockDirectory = Resolve-Path -Relative -Path "$PSScriptRoot/mock"
    $script:commonParam = @{
        DefaultDeploymentConfigPath = "$mockDirectory/default.deploymentconfig.json"
    }
}

Describe "Get-DeploymentConfig.ps1" {
    Context "With .json deploymentconfig file" {
        BeforeAll {
            $script:param = @{
                DeploymentDirectoryPath = "$mockDirectory/deployments/deployment-config/json"
                DeploymentFileName      = "dev.bicepparam"
            }

            $script:res = Get-DeploymentConfig @commonParam @param
        }

        It "The 'name' property should be 'deployment-name'" {
            $res.name | Should -Be "deployment-name"
        }
    }

    Context "With .jsonc deploymentconfig file" {
        BeforeAll {
            $script:param = @{
                DeploymentDirectoryPath = "$mockDirectory/deployments/deployment-config/jsonc"
                DeploymentFileName      = "dev.bicepparam"
            }

            $script:res = Get-DeploymentConfig @commonParam @param
        }

        It "The 'name' property should be 'deployment-name'" {
            $res.name | Should -Be "deployment-name"
        }
    }

    Context "With conflicting deploymentconfig files" {
        BeforeAll {
            $script:param = @{
                DeploymentDirectoryPath = "$mockDirectory/deployments/deployment-config/conflict"
                DeploymentFileName      = "dev.bicepparam"
            }
        }

        It "Should throw 'Found multiple deploymentconfig files.'" {
            { Get-DeploymentConfig @commonParam @param } | Should -Throw "*Found multiple deploymentconfig files.*"
        }
    }

    Context "With deploymentconfig value" {
        BeforeAll {
            $script:param = @{
                DeploymentDirectoryPath = "$mockDirectory/deployments/deployment-config/default"
                DeploymentFileName      = "dev.bicepparam"
            }

            $script:res = Get-DeploymentConfig @commonParam @param
        }

        It "The 'name' property should be 'deployment-name'" {
            $res.name | Should -Be "deployment-name"
        }
    }
    
    Context "With default.deploymentconfig value override" {
        BeforeAll {
            $script:param = @{
                DeploymentDirectoryPath = "$mockDirectory/deployments/deployment-config/default"
                DeploymentFileName      = "dev.bicepparam"
            }

            $script:res = Get-DeploymentConfig @commonParam @param
        }

        It "The 'location' property should be 'northeurope'" {
            $res.location | Should -Be "northeurope"
        }
    }

    Context "With default.deploymentconfig value fallback" {
        BeforeAll {
            $script:param = @{
                DeploymentDirectoryPath = "$mockDirectory/deployments/deployment-config/default"
                DeploymentFileName      = "dev.bicepparam"
            }

            $script:res = Get-DeploymentConfig @commonParam @param
        }

        It "The 'azureCliVersion' property should be '2.68.0'" {
            $res.azureCliVersion | Should -Be "2.68.0"
        }
    }
}
