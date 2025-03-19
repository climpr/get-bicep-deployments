BeforeAll {
    Import-Module $PSScriptRoot/../support-functions.psm1 -Force
    
    # Create test root directory
    $script:testRoot = Join-Path $TestDrive 'mock'
    New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

    # Set up common parameters
    $script:deploymentsRootDirectory = Join-Path -Path $testRoot -ChildPath "deployments"
    $script:commonParams = @{
        Quiet                    = $true
        DeploymentsRootDirectory = $deploymentsRootDirectory
    }

    function New-FileStructure {
        param (
            [Parameter(Mandatory)]
            [string] $Path,
            
            [Parameter(Mandatory)]
            [System.Collections.IDictionary] $Deployments
        )
    
        # Create root directory if it doesn't exist
        if (!(Test-Path -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
    
        foreach ($key in $Deployments.Keys) {
            $itemPath = Join-Path -Path $Path -ChildPath $key
            
            if ($Deployments[$key] -is [System.Collections.IDictionary]) {
                # If value is hashtable, recurse into new directory
                New-FileStructure -Path $itemPath -Deployments $Deployments[$key]
            }
            else {
                # If value is string, create file with content
                Set-Content -Path $itemPath -Value $Deployments[$key] -Force
            }
        }
    }
}

AfterAll {
    Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue -ProgressAction Ignore
}

Describe "Get-BicepDeployments.ps1" {
    BeforeEach {
        New-Item -Path $deploymentsRootDirectory -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $deploymentsRootDirectory -Recurse -Force -ErrorAction SilentlyContinue -ProgressAction Ignore
    }

    Context "When mode is 'Modified'" {
        It "Should handle <scenario> correctly" -TestCases @(
            # No files modified
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
            New-FileStructure -Path $deploymentsRootDirectory -Deployments $mock

            # Resolve relative paths
            $changedFiles = $changedFiles | ForEach-Object { Resolve-Path -Path (Join-Path $deploymentsRootDirectory $_) -Relative }

            # Run script
            $res = ./src/Get-BicepDeployments.ps1 @commonParams -EventName "push" -Mode "Modified" -ChangedFiles $changedFiles

            # Assert
            $res -is [System.Object[]] | Should -BeTrue
            $res | Should -HaveCount $expected.Length
            $res.Name | Should -Be $expected
        }
    }

    Context "When 'Environment' filter is applied" {
        It "Should return only the environment specific deployments" {
            # Create mock deployments
            New-FileStructure -Path $deploymentsRootDirectory -Deployments @{
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
            $res = ./src/Get-BicepDeployments.ps1 @commonParams -EventName "workflow_dispatch" -Mode "All" -Environment "prod"

            # Assert
            $res -is [System.Object[]] | Should -BeTrue
            $res | Should -HaveCount 2
            $res.Name | Should -Be @("deployment-2-prod", "deployment-3-prod")
        }
    }

    Context "When mode is 'All'" {
        It "Should return all deployments" {
            # Create mock deployments
            New-FileStructure -Path $deploymentsRootDirectory -Deployments @{
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
            $res = ./src/Get-BicepDeployments.ps1 @commonParams -EventName "schedule" -Mode "All"

            # Assert
            $res -is [System.Object[]] | Should -BeTrue
            $res | Should -HaveCount 4
            $res.Name | Should -Be @("deployment-1-dev", "deployment-2-dev", "deployment-2-prod", "deployment-3-prod")
        }
    }

    Context "When 'Pattern' filter is applied" {
        Context "And no 'Environment' filter is applied" {
            It "Should return only the deployments matching the pattern" {
                # Create mock deployments
                New-FileStructure -Path $deploymentsRootDirectory -Deployments @{
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
                $res = ./src/Get-BicepDeployments.ps1 @commonParams -EventName "workflow_dispatch" -Mode "All" -Pattern "deployment-2"
                
                # Assert
                $res -is [System.Object[]] | Should -BeTrue
                $res | Should -HaveCount 2
                $res.Name | Should -Be @("deployment-2-dev", "deployment-2-prod")
            }
        }
        Context "And 'Environment' filter is applied" {
            It "Should return only the deployments matching the pattern and environment" {
                # Create mock deployments
                New-FileStructure -Path $deploymentsRootDirectory -Deployments @{
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
                $res = ./src/Get-BicepDeployments.ps1 @commonParams -EventName "workflow_dispatch" -Mode "All" -Pattern "deployment-2" -Environment "prod"
                
                # Assert
                $res -is [System.Object[]] | Should -BeTrue
                $res | Should -HaveCount 1
                $res.Name | Should -Be @("deployment-2-prod")
            }
        }
    }
}
