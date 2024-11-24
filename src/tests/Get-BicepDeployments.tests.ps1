BeforeAll {
    Import-Module $PSScriptRoot/../support-functions.psm1
}

Describe "Get-BicepDeployments.ps1" {
    BeforeAll {
        $script:mockDirectory = "$PSScriptRoot/mock"
    }

    Context "When mode is 'Modified'" {
        BeforeAll {
            $script:param = @{
                Quiet                    = $true
                EventName                = "push"
                Mode                     = "Modified"
                DeploymentsRootDirectory = "$mockDirectory/deployments"
                ChangedFiles             = @(
                    "$mockDirectory/deployments/workload-local/.bicep/submodule.bicep"
                    "$mockDirectory/deployments/workload-remote-param/prod.bicepparam"
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
                DeploymentsRootDirectory = "$mockDirectory/deployments"
            }

            $script:res = ./src/Get-BicepDeployments.ps1 @param
        }

        It "Should contain workload-local-dev, workload-remote-modules-prod, workload-remote-param-dev and workload-remote-param-prod" {
            $res | Should -HaveCount 4
            $res.Name | Should -Contain "workload-local-dev"
            $res.Name | Should -Contain "workload-remote-modules-prod"
            $res.Name | Should -Contain "workload-remote-param-dev"
            $res.Name | Should -Contain "workload-remote-param-prod"
        }
    }

    Context "With pattern filters applied" {
        BeforeAll {
            $script:param = @{
                Quiet                    = $true
                EventName                = "workflow_dispatch"
                Mode                     = "All"
                DeploymentsRootDirectory = "$mockDirectory/deployments"
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

    Context "With conflicting deploymentconfig files" {
        BeforeAll {
            $script:deploymentPath = "$mockDirectory/deployments/workload-multi-deploymentconfig"
            $script:param = @{
                Quiet                    = $true
                EventName                = "workflow_dispatch"
                Mode                     = "All"
                DeploymentsRootDirectory = "$mockDirectory/deployments"
                Pattern                  = "workload-multi-deploymentconfig"
                Environment              = "dev"
            }
            Copy-Item -Path "$deploymentPath/deploymentconfig.json" -Destination "$deploymentPath/deploymentconfig.jsonc"
        }

        It "Should throw 'Found multiple deploymentconfig files.'" {
            { ./src/Get-BicepDeployments.ps1 @param } | Should -Throw "*Found multiple deploymentconfig files.*"
        }

        AfterAll {
            Remove-Item -Path "$script:deploymentPath/deploymentconfig.jsonc" -Confirm:$false
        }
    }
}