BeforeAll {
    Import-Module $PSScriptRoot/../support-functions.psm1 -Force
}

Describe "Resolve-TemplateDeploymentScope" {
    BeforeAll {
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'test'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
    }

    BeforeEach {
        $script:bicepFile = Join-Path $testRoot 'main.bicep'
        $script:parameterFile = Join-Path $testRoot 'main.bicepparam'
    }

    AfterEach {
        Remove-Item -Path $bicepFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $parameterFile -Force -ErrorAction SilentlyContinue
    }

    Context "Local template scope resolution" {
        It "Should resolve <Expected> scope" -TestCases @(
            @{
                BicepContent = "param location string = 'westeurope'"
                Config       = @{ resourceGroupName = 'mockResourceGroup' }
                Expected     = 'resourceGroup'
            }
            @{
                BicepContent = "targetScope = 'subscription'`nparam location string = 'westeurope'"
                Config       = @{}
                Expected     = 'subscription'
            }
            @{
                BicepContent = "targetScope = 'managementGroup'`nparam location string = 'westeurope'"
                Config       = @{ managementGroupId = 'mockManagementGroup' }
                Expected     = 'managementGroup'
            }
            @{
                BicepContent = "targetScope = 'tenant'`nparam location string = 'westeurope'"
                Config       = @{}
                Expected     = 'tenant'
            }
        ) {
            param($BicepContent, $Config, $Expected)
            
            Set-Content -Path $bicepFile -Value $BicepContent
            Set-Content -Path $parameterFile -Value "using 'main.bicep'"

            $params = @{
                DeploymentFilePath = $parameterFile
                DeploymentConfig   = $Config
            }

            $templateDeploymentScope = Resolve-TemplateDeploymentScope @params
            $templateDeploymentScope | Should -Be $Expected
        }
    }

    Context "DeploymentConfig validation" {
        It "Should throw when <Scope> scope is specified without <Required> in deploymentconfig.jsonc" -TestCases @(
            @{
                Scope         = 'resourceGroup'
                BicepContent  = "param location string = 'westeurope'"
                Required      = 'resourceGroupName'
                ExpectedError = "*Target scope is resourceGroup, but resourceGroupName property is not present*"
            }
            @{
                Scope         = 'managementGroup'
                BicepContent  = "targetScope = 'managementGroup'`nparam location string = 'westeurope'"
                Required      = 'managementGroupId'
                ExpectedError = "*Target scope is managementGroup, but managementGroupId property is not present*"
            }
        ) {
            param($BicepContent, $ExpectedError)

            Set-Content -Path $bicepFile -Value $BicepContent
            Set-Content -Path $parameterFile -Value "using 'main.bicep'"

            $params = @{
                DeploymentFilePath = $parameterFile
                DeploymentConfig   = @{}
            }

            { Resolve-TemplateDeploymentScope @params } | Should -Throw $ExpectedError
        }
    }

    Context "Keyword position validation" {
        It "Should resolve subscription scope" {
            "metadata author = 'author'`ntargetScope = 'subscription'" | Set-Content -Path $bicepFile
            "metadata author = 'author'`nusing 'main.bicep'" | Set-Content -Path $parameterFile

            $params = @{
                DeploymentFilePath = $parameterFile
                DeploymentConfig   = @{}
            }

            $templateDeploymentScope = Resolve-TemplateDeploymentScope @params
            $templateDeploymentScope | Should -Be 'subscription'
        }
    }

    Context "Input file types" {
        It "Should resolve subscription scope for .bicep file" {
            "targetScope = 'subscription'" | Set-Content -Path $bicepFile
            
            $params = @{
                DeploymentFilePath = $bicepFile
                DeploymentConfig   = @{}
            }
            
            $templateDeploymentScope = Resolve-TemplateDeploymentScope @params
            $templateDeploymentScope | Should -Be 'subscription'
        }
        
        It "Should resolve subscription scope for .bicepparam file" {
            "targetScope = 'subscription'" | Set-Content -Path $bicepFile
            "using 'main.bicep'" | Set-Content -Path $parameterFile

            $params = @{
                DeploymentFilePath = $parameterFile
                DeploymentConfig   = @{}
            }

            $templateDeploymentScope = Resolve-TemplateDeploymentScope @params
            $templateDeploymentScope | Should -Be 'subscription'
        }
    }
}
