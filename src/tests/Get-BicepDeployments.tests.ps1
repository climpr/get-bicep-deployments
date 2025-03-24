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

Describe "Get-BicepDeployments" {
    BeforeEach {
        # Create mock root directory
        $script:testRoot = Join-Path $TestDrive 'mock'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        
        # Set up common parameters
        $script:commonParams = @{
            Quiet                    = $true
            DeploymentsRootDirectory = $testRoot
        }
    }

    AfterEach {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue -ProgressAction SilentlyContinue
    }

    Context "When mode is 'Modified'" {
        It "Should handle <scenario> correctly" -TestCases @(
            # # No files modified
            @{
                scenario     = "no files modified"
                changedFiles = @()
                expected     = @()
                mock         = @{
                    'deployment-1' = @{
                        'main.bicep'     = "targetScope = 'subscription'"
                        'dev.bicepparam' = "using 'main.bicep'"
                    }
                }
            }
            # Single file in a single deployment
            @{
                scenario     = "single file in a single deployment modified"
                changedFiles = @("deployment-2/main.bicep")
                expected     = @("deployment-2-dev")
                mock         = @{
                    'deployment-1' = @{
                        'main.bicep'     = "targetScope = 'subscription'"
                        'dev.bicepparam' = "using 'main.bicep'"
                    }
                    'deployment-2' = @{
                        'main.bicep'     = "targetScope = 'subscription'"
                        'dev.bicepparam' = "using 'main.bicep'"
                    }
                }
            }
            # referenced file modified
            @{
                scenario     = "single file in a single deployment modified"
                changedFiles = @("deployment-1/modules/module1.bicep")
                expected     = @("deployment-1-dev")
                mock         = @{
                    'deployment-1' = @{
                        'main.bicep'     = "targetScope = 'subscription'`nmodule module1 'modules/module1.bicep' = { name: 'module1' }"
                        'dev.bicepparam' = "using 'main.bicep'"
                        'modules'        = @{
                            'module1.bicep' = "targetScope = 'subscription'"
                        }
                    }
                    'deployment-2' = @{
                        'main.bicep'     = "targetScope = 'subscription'"
                        'dev.bicepparam' = "using 'main.bicep'"
                    }
                }
            }
            # Multiple files in the same deployment
            @{
                scenario     = "multiple files in the same deployment modified"
                changedFiles = @( "deployment-2/main.bicep", "deployment-2/dev.bicepparam" )
                expected     = @("deployment-2-dev")
                mock         = @{
                    'deployment-1' = @{
                        'main.bicep'     = "targetScope = 'subscription'"
                        'dev.bicepparam' = "using 'main.bicep'"
                    }
                    'deployment-2' = @{
                        'main.bicep'     = "targetScope = 'subscription'"
                        'dev.bicepparam' = "using 'main.bicep'"
                    }
                }
            }
            # Multiple files across multiple deployments
            @{
                scenario     = "multiple files across multiple deployments modified"
                changedFiles = @( "deployment-1/main.bicep", "deployment-2/dev.bicepparam" )
                expected     = @("deployment-1-dev", "deployment-2-dev")
                mock         = @{
                    'deployment-1' = @{
                        'main.bicep'     = "targetScope = 'subscription'"
                        'dev.bicepparam' = "using 'main.bicep'"
                    }
                    'deployment-2' = @{
                        'main.bicep'     = "targetScope = 'subscription'"
                        'dev.bicepparam' = "using 'main.bicep'"
                    }
                }
            }
        ) {
            param ($changedFiles, $expected, $mock)

            # Create mock deployments
            New-FileStructure -Path $testRoot -Structure $mock
            
            # Resolve relative paths
            $changedFiles = $changedFiles | ForEach-Object { Resolve-Path -Path (Join-Path $testRoot $_) -Relative }

            # Run script
            $result = Get-BicepDeployments @commonParams -EventName "push" -Mode "Modified" -ChangedFiles $changedFiles

            # Assert
            $result -is [System.Object[]] | Should -BeTrue
            $result | Should -HaveCount $expected.Length
            $result.Name | Should -BeExactly $expected
        }
    }

    Context "When 'Environment' filter is applied" {
        It "Should return only the environment specific deployments" {
            # Create mock deployments
            New-FileStructure -Path $testRoot -Structure @{
                'deployment-1' = @{
                    'main.bicep'     = "targetScope = 'subscription'"
                    'dev.bicepparam' = "using 'main.bicep'"
                }
                'deployment-2' = @{
                    'main.bicep'      = "targetScope = 'subscription'"
                    'dev.bicepparam'  = "using 'main.bicep'"
                    'prod.bicepparam' = "using 'main.bicep'"
                }
                'deployment-3' = @{
                    'main.bicep'      = "targetScope = 'subscription'"
                    'prod.bicepparam' = "using 'main.bicep'"
                }
            }

            # Run script
            $result = Get-BicepDeployments @commonParams -EventName "workflow_dispatch" -Mode "All" -Environment "prod"

            # Assert
            $result -is [System.Object[]] | Should -BeTrue
            $result | Should -HaveCount 2
            $result.Name | Should -BeExactly @("deployment-2-prod", "deployment-3-prod")
        }
    }

    Context "When mode is 'All'" {
        It "Should return all deployments" {
            # Create mock deployments
            New-FileStructure -Path $testRoot -Structure @{
                'deployment-1' = @{
                    'main.bicep'     = "targetScope = 'subscription'"
                    'dev.bicepparam' = "using 'main.bicep'"
                }
                'deployment-2' = @{
                    'main.bicep'      = "targetScope = 'subscription'"
                    'dev.bicepparam'  = "using 'main.bicep'"
                    'prod.bicepparam' = "using 'main.bicep'"
                }
                'deployment-3' = @{
                    'main.bicep'      = "targetScope = 'subscription'"
                    'prod.bicepparam' = "using 'main.bicep'"
                }
            }

            # Run script
            $result = Get-BicepDeployments @commonParams -EventName "schedule" -Mode "All"

            # Assert
            $result -is [System.Object[]] | Should -BeTrue
            $result | Should -HaveCount 4
            $result.Name | Should -BeExactly @("deployment-1-dev", "deployment-2-dev", "deployment-2-prod", "deployment-3-prod")
        }
    }

    Context "When 'Pattern' filter is applied" {
        Context "And no 'Environment' filter is applied" {
            It "Should return only the deployments matching the pattern" {
                # Create mock deployments
                New-FileStructure -Path $testRoot -Structure @{
                    'deployment-1' = @{
                        'main.bicep'     = "targetScope = 'subscription'"
                        'dev.bicepparam' = "using 'main.bicep'"
                    }
                    'deployment-2' = @{
                        'main.bicep'      = "targetScope = 'subscription'"
                        'dev.bicepparam'  = "using 'main.bicep'"
                        'prod.bicepparam' = "using 'main.bicep'"
                    }
                }
                
                # Run script
                $result = Get-BicepDeployments @commonParams -EventName "workflow_dispatch" -Mode "All" -Pattern "deployment-2"
                
                # Assert
                $result -is [System.Object[]] | Should -BeTrue
                $result | Should -HaveCount 2
                $result.Name | Should -BeExactly @("deployment-2-dev", "deployment-2-prod")
            }
        }
        Context "And 'Environment' filter is applied" {
            It "Should return only the deployments matching the pattern and environment" {
                # Create mock deployments
                New-FileStructure -Path $testRoot -Structure @{
                    'deployment-1' = @{
                        'main.bicep'     = "targetScope = 'subscription'"
                        'dev.bicepparam' = "using 'main.bicep'"
                    }
                    'deployment-2' = @{
                        'main.bicep'      = "targetScope = 'subscription'"
                        'dev.bicepparam'  = "using 'main.bicep'"
                        'prod.bicepparam' = "using 'main.bicep'"
                    }
                }
                
                # Run script
                $result = Get-BicepDeployments @commonParams -EventName "workflow_dispatch" -Mode "All" -Pattern "deployment-2" -Environment "prod"
                
                # Assert
                $result -is [System.Object[]] | Should -BeTrue
                $result | Should -HaveCount 1
                $result.Name | Should -BeExactly @("deployment-2-prod")
            }
        }
    }
}
