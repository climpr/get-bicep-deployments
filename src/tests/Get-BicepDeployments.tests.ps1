BeforeAll {
    Import-Module $PSScriptRoot/../support-functions.psm1 -Force
    $script:mockDirectory = Resolve-Path -Relative -Path "$PSScriptRoot/mock"
}

Describe "Get-BicepDeployments.ps1" {
    Context "When mode is 'Modified'" {
        BeforeAll {
            $script:param = @{
                Quiet                    = $true
                EventName                = "push"
                Mode                     = "Modified"
                DeploymentsRootDirectory = "$mockDirectory/deployments/deployment"
                ChangedFiles             = @(
                    "$mockDirectory/deployments/deployment/workload-local/.bicep/submodule.bicep"
                    "$mockDirectory/deployments/deployment/workload-remote-param/prod.bicepparam"
                )
            }

            $script:res = ./src/Get-BicepDeployments.ps1 @param
        }

        It "Should contain workload-local-dev and workload-remote-param-prod" {
            $res | Should -HaveCount 2
            $res.Name | Should -Contain "workload-local-dev"
            $res.Name | Should -Contain "workload-remote-param-prod"
        }
    }
    
    Context "When no filters are aplied" {
        BeforeAll {
            $script:param = @{
                Quiet                    = $true
                EventName                = "schedule"
                Mode                     = "All"
                DeploymentsRootDirectory = "$mockDirectory/deployments/deployment"
            }

            $script:res = ./src/Get-BicepDeployments.ps1 @param
        }

        It "Should contain all the deployments" {
            $res | Should -HaveCount 8
            $res.Name | Should -Contain "workload-local-dev"
            $res.Name | Should -Contain "workload-remote-modules-prod"
            $res.Name | Should -Contain "workload-remote-param-dev"
            $res.Name | Should -Contain "workload-remote-param-prod"
            $res.Name | Should -Contain "no-param-single-dev"
            $res.Name | Should -Contain "no-param-multi-dev"
            $res.Name | Should -Contain "no-param-multi-prod"
            $res.Name | Should -Contain "extendable-param-multi-dev"
        }
    }

    Context "With pattern filters applied" {
        BeforeAll {
            $script:param = @{
                Quiet                    = $true
                EventName                = "workflow_dispatch"
                Mode                     = "All"
                DeploymentsRootDirectory = "$mockDirectory/deployments/deployment"
                Pattern                  = "workload-remote-.+"
                Environment              = "prod"
            }

            $script:res = ./src/Get-BicepDeployments.ps1 @param
        }

        It "Should contain workload-remote-modules and workload-remote-param" {
            $res | Should -HaveCount 2
            $res.Name | Should -Contain "workload-remote-modules-prod"
            $res.Name | Should -Contain "workload-remote-param-prod"
        }
    }
    
    Context "When no .bicepparam files exists and a single .bicep file exists" {
        BeforeAll {
            $script:param = @{
                Quiet                    = $true
                EventName                = "schedule"
                Mode                     = "All"
                DeploymentsRootDirectory = "$mockDirectory/deployments/deployment"
            }

            $script:res = ./src/Get-BicepDeployments.ps1 @param
        }

        It "Should contain all the deployments" {
            $res | Should -HaveCount 8
            $res.Name | Should -Contain "workload-local-dev"
            $res.Name | Should -Contain "workload-remote-modules-prod"
            $res.Name | Should -Contain "workload-remote-param-dev"
            $res.Name | Should -Contain "workload-remote-param-prod"
            $res.Name | Should -Contain "no-param-single-dev"
            $res.Name | Should -Contain "no-param-multi-dev"
            $res.Name | Should -Contain "no-param-multi-prod"
            $res.Name | Should -Contain "extendable-param-multi-dev"
        }
    }
}