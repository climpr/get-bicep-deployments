BeforeAll {
    if ((Get-PSResourceRepository -Name PSGallery).Trusted -eq $false) {
        Set-PSResourceRepository -Name PSGallery -Trusted -Confirm:$false
    }
    if ((Get-PSResource -Name Bicep -ErrorAction Ignore).Version -lt "2.7.0") {
        Install-PSResource -Name Bicep
    }
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

Describe "Resolve-DeploymentConfig" {
    BeforeEach {
        $script:testRoot = Join-Path $TestDrive 'mock'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

        # Create default deploymentconfig.jsonc file
        $script:defaultDeploymentConfigPath = Join-Path $testRoot "default.deploymentconfig.jsonc"
        $script:defaultDeploymentConfig = [ordered]@{
            '$schema'         = "https://raw.githubusercontent.com/climpr/climpr-schemas/main/schemas/v1.0.0/bicep-deployment/deploymentconfig.json#"
            'location'        = "westeurope"
            'azureCliVersion' = "2.68.0"
        }
        $defaultDeploymentConfig | ConvertTo-Json | Out-File -FilePath $defaultDeploymentConfigPath

        $script:commonParams = @{
            DefaultDeploymentConfigPath = $defaultDeploymentConfigPath
            GitHubEventName             = "workflow_dispatch"
            Quiet                       = $true
        }
    }

    AfterEach {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue -ProgressAction SilentlyContinue
    }

    # MARK: Input files
    Context "Handle input files correctly" {
        It "Should handle .bicep file correctly" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep' = "targetScope = 'subscription'"
            }
            
            $relativeRoot = Resolve-Path -Relative -Path $testRoot
            $result = Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/main.bicep"
            $result.TemplateReference | Should -BeExactly "$relativeRoot/main.bicep"
            $result.ParameterFile | Should -BeNullOrEmpty
        }
        
        It "Should handle .bicepparam file correctly" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'      = "targetScope = 'subscription'"
                'prod.bicepparam' = "using 'main.bicep'"
            }
            
            $relativeRoot = Resolve-Path -Relative -Path $testRoot
            $result = Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
            $result.TemplateReference | Should -BeExactly "main.bicep"
            $result.ParameterFile | Should -BeExactly "$relativeRoot/prod.bicepparam"
        }
    }

    # MARK: Scopes
    Context "Handle scopes correctly" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario = "'resourceGroup' scope"
                expected = "resourceGroup"
                mock     = @{
                    'main.bicep'             = "targetScope = 'resourceGroup'"
                    'deploymentconfig.jsonc' = @{ resourceGroupName = 'mock-rg' } | ConvertTo-Json
                }
            }
            @{
                scenario = "'subscription' scope"
                expected = "subscription"
                mock     = @{
                    'main.bicep' = "targetScope = 'subscription'"
                }
            }
            @{
                scenario = "'managementGroup' scope"
                expected = "managementGroup"
                mock     = @{
                    'main.bicep'             = "targetScope = 'managementGroup'"
                    'deploymentconfig.jsonc' = @{ managementGroupId = 'mock-mg' } | ConvertTo-Json
                }
            }
            @{
                scenario = "'tenant' scope"
                expected = "tenant"
                mock     = @{
                    'main.bicep' = "targetScope = 'tenant'"
                }
            }
        ) {
            param ($mock, $expected)
            New-FileStructure -Path $testRoot -Structure $mock
            $result = Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/main.bicep"
            $result.Scope | Should -BeExactly $expected
        }

        It "Should fail if target scope is 'tenant' and type is 'deploymentStack'" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'             = "targetScope = 'tenant'"
                'deploymentconfig.jsonc' = @{ type = "deploymentStack" } | ConvertTo-Json
            }

            { Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/main.bicep" }
            | Should -Throw "Deployment stacks are not supported for tenant scoped deployments."
        }
    }

    # MARK: Remote templates
    Context "Handle direct .bicepparam remote template reference correctly" {
        It "Should handle remote Azure Container Registry (ACR) template correctly" {
            New-FileStructure -Path $testRoot -Structure @{
                'prod.bicepparam' = "using 'br/public:avm/res/resources/resource-group:0.4.1'"
            }

            $result = Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
            $result.TemplateReference | Should -BeExactly 'br/public:avm/res/resources/resource-group:0.4.1'
        }

        #? No authenticated pipeline to run test. Hence, template specs cannot be restored.
        # It "Should handle remote Template Specs correctly" {
        #     New-FileStructure -Path $testRoot -Structure @{
        #         'prod.bicepparam' = "using 'ts:resourceId:tag'"
        #     }
        #     $result = Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
        #     $result.TemplateReference | Should -BeExactly 'ts:resourceId:tag'
        # }
    }

    # MARK: Common parameters
    Context "Handle common parameters" {
        Context "'Deploy' parameter" {
            It "Should handle <scenario> correctly" -TestCases @(
                @{
                    scenario         = "deploymentConfig.disabled not specified (default)"
                    deploymentConfig = @{}
                    expected         = $true
                }
                @{
                    scenario         = "deploymentConfig.disabled set to null"
                    deploymentConfig = @{ disabled = $null }
                    expected         = $true
                }
                @{
                    scenario         = "deploymentConfig.disabled set to false"
                    deploymentConfig = @{ disabled = $false }
                    expected         = $true
                }
                @{
                    scenario         = "deploymentConfig.disabled set to true"
                    deploymentConfig = @{ disabled = $true }
                    expected         = $false
                }
                @{
                    scenario         = "deploymentConfig.triggers.<eventName>.disabled set to true"
                    deploymentConfig = @{ disabled = $true; triggers = @{ workflow_dispatch = @{ disabled = $true } } }
                    expected         = $false
                }
                @{
                    scenario         = "deploymentConfig.triggers.<eventName>.disabled set to false but deploymentConfig.disabled set to true"
                    deploymentConfig = @{ disabled = $true; triggers = @{ workflow_dispatch = @{ disabled = $false } } }
                    expected         = $false
                }
            ) {
                param ($scenario, $deploymentConfig, $expected)
                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'             = "targetScope = 'subscription'"
                    'prod.bicepparam'        = "using 'main.bicep'"
                    'deploymentconfig.jsonc' = $deploymentConfig | ConvertTo-Json
                }
                $result = Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
                $result.Deploy | Should -BeExactly $expected
            }
        }
    }

    # MARK: Deployment
    Context "When deployment is a normal deployment" {
        Context "When the deployment type is 'deployment'" {
            It "It should handle all properties correctly" {
                New-FileStructure -Path $testRoot -Structure @{
                    'testdeploy' = @{
                        'main.bicep'      = "targetScope = 'subscription'"
                        'prod.bicepparam' = "using 'main.bicep'"
                    }
                }

                $paramFileRelative = Resolve-Path -Relative -Path "$testRoot/testdeploy/prod.bicepparam"
                $deploymentName = "testdeploy-prod-$(git rev-parse --short HEAD)" # Name of the temporary parent directory + 'prod' from prod.bicepparam + git short hash

                $properties = [ordered]@{
                    Deploy            = $true
                    AzureCliVersion   = $defaultDeploymentConfig.azureCliVersion
                    Type              = "deployment"
                    Scope             = "subscription"
                    ParameterFile     = $paramFileRelative
                    TemplateReference = 'main.bicep'
                    Name              = $deploymentName
                    Location          = "westeurope"
                    ManagementGroupId = $null
                    ResourceGroupName = $null
                    AzureCliCommand   = "az deployment sub create --location westeurope --name $deploymentName --parameters $paramFileRelative"
                }
                
                $result = Resolve-DeploymentConfig @commonParams -DeploymentFilePath $paramFileRelative
                foreach ($key in $properties.Keys) {
                    $result.$key | Should -BeExactly $properties[$key]
                }
            }
        }

        # MARK: Deployment 'DeploymentWhatIf'
        Context "Handle 'DeploymentWhatIf' parameter" {
            It "Should handle <scenario> correctly" -TestCases @(
                @{
                    scenario = "no 'DeploymentWhatIf' parameter"
                    expected = "^(?!.*--what-if).*$"
                }
                @{
                    scenario         = "false 'DeploymentWhatIf' parameter"
                    deploymentWhatIf = $false
                    expected         = "^(?!.*--what-if).*$"
                }
                @{
                    scenario         = "true 'DeploymentWhatIf' parameter"
                    deploymentWhatIf = $true
                    expected         = "--what-if"
                }
            ) {
                param ($scenario, $deploymentWhatIf, $expected)
            
                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'      = "targetScope = 'subscription'"
                    'prod.bicepparam' = "using 'main.bicep'"
                }

                $deploymentWhatIfParam = @{}
                if ($deploymentWhatIf) {
                    $deploymentWhatIfParam = @{ DeploymentWhatIf = $deploymentWhatIf }
                }

                Resolve-DeploymentConfig @commonParams @deploymentWhatIfParam -DeploymentFilePath "$testRoot/prod.bicepparam"
                | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
            }
        }
    }

    # MARK: Stack
    Context "When deployment is a Deployment stack" {
        Context "When the deployment type is 'deploymentStack'" {
            It "It should handle all properties correctly" {
                New-FileStructure -Path $testRoot -Structure @{
                    'testdeploy' = @{
                        'main.bicep'             = "targetScope = 'subscription'"
                        'prod.bicepparam'        = "using 'main.bicep'"
                        'deploymentconfig.jsonc' = @{ type = "deploymentStack" } | ConvertTo-Json
                    }
                }

                $paramFileRelative = Resolve-Path -Relative -Path "$testRoot/testdeploy/prod.bicepparam"
                $deploymentName = "testdeploy-prod-$(git rev-parse --short HEAD)" # Name of the temporary parent directory + 'prod' from prod.bicepparam + git short hash

                $properties = [ordered]@{
                    Deploy            = $true
                    AzureCliVersion   = $defaultDeploymentConfig.azureCliVersion
                    Type              = "deploymentStack"
                    Scope             = "subscription"
                    ParameterFile     = $paramFileRelative
                    TemplateReference = 'main.bicep'
                    Name              = $deploymentName
                    Location          = "westeurope"
                    ManagementGroupId = $null
                    ResourceGroupName = $null
                    AzureCliCommand   = "az stack sub create --location westeurope --name $deploymentName --parameters $paramFileRelative --yes --action-on-unmanage detachAll --deny-settings-mode none --description `"`" --tags `"`""
                }

                $result = Resolve-DeploymentConfig @commonParams -DeploymentFilePath $paramFileRelative
                foreach ($key in $properties.Keys) {
                    $result.$key | Should -BeExactly $properties[$key]
                }
            }
        }
        
        # MARK: Stack 'description'
        Context "When handling stack 'description' property" {
            It "Should handle <scenario> correctly" -TestCases @(
                @{
                    scenario = "no description property"
                    expected = '--description ""'
                }
                @{
                    scenario    = "null description property"
                    description = $null
                    expected    = '--description ""'
                }
                @{
                    scenario    = "empty description property"
                    description = ""
                    expected    = '--description ""'
                }
                @{
                    scenario    = "non-empty description property"
                    description = "mock-description"
                    expected    = '--description mock-description'
                }
            ) {
                param ($scenario, $description, $expected)
                
                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'             = "targetScope = 'subscription'"
                    'prod.bicepparam'        = "using 'main.bicep'"
                    'deploymentconfig.jsonc' = @{
                        type        = "deploymentStack"
                        description = $description
                    } | ConvertTo-Json
                }
                
                Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
                | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
            }
        }

        # MARK: Stack 'bypassStackOutOfSyncError'
        Context "When handling stack 'bypassStackOutOfSyncError' property" {
            It "Should handle <scenario> correctly" -TestCases @(
                @{
                    scenario = "no bypassStackOutOfSyncError property"
                    expected = "^(?!.*--bypass-stack-out-of-sync-error).*$"
                }
                @{
                    scenario                  = "null bypassStackOutOfSyncError property"
                    bypassStackOutOfSyncError = $null
                    expected                  = "^(?!.*--bypass-stack-out-of-sync-error).*$"
                }
                @{
                    scenario                  = "false bypassStackOutOfSyncError"
                    bypassStackOutOfSyncError = $false
                    expected                  = "^(?!.*--bypass-stack-out-of-sync-error).*$"
                }
                @{
                    scenario                  = "true bypassStackOutOfSyncError"
                    bypassStackOutOfSyncError = $true
                    expected                  = '--bypass-stack-out-of-sync-error'
                }
            ) {
                param ($scenario, $bypassStackOutOfSyncError, $expected)
                
                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'             = "targetScope = 'subscription'"
                    'prod.bicepparam'        = "using 'main.bicep'"
                    'deploymentconfig.jsonc' = @{
                        type                      = "deploymentStack"
                        bypassStackOutOfSyncError = $bypassStackOutOfSyncError
                    } | ConvertTo-Json
                }
                
                Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
                | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
            }
        }

        # MARK: Stack 'denySettings.applyToChildScopes'
        Context "When handling stack 'denySettings.applyToChildScopes' property" {
            It "Should handle <scenario> correctly" -TestCases @(
                @{
                    scenario = "no applyToChildScopes property"
                    expected = "^(?!.*--deny-settings-apply-to-child-scopes).*$"
                }
                @{
                    scenario           = "null applyToChildScopes property"
                    applyToChildScopes = $null
                    expected           = "^(?!.*--deny-settings-apply-to-child-scopes).*$"
                }
                @{
                    scenario           = "false applyToChildScopes"
                    applyToChildScopes = $false
                    expected           = "^(?!.*--deny-settings-apply-to-child-scopes).*$"
                }
                @{
                    scenario           = "true applyToChildScopes"
                    applyToChildScopes = $true
                    expected           = '--deny-settings-apply-to-child-scopes'
                }
            ) {
                param ($scenario, $applyToChildScopes, $expected)
                
                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'             = "targetScope = 'subscription'"
                    'prod.bicepparam'        = "using 'main.bicep'"
                    'deploymentconfig.jsonc' = @{
                        type         = "deploymentStack"
                        denySettings = @{
                            mode               = "denyDelete"
                            applyToChildScopes = $applyToChildScopes
                        }
                    } | ConvertTo-Json
                }
                
                Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
                | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
            }
        }

        # MARK: Stack 'denySettings.excludedActions'
        Context "When handling stack 'denySettings.excludedActions' property" {
            It "Should handle <scenario> correctly" -TestCases @(
                @{
                    scenario = "no excludedActions property"
                    expected = "^(?!.*--deny-settings-excluded-actions).*$"
                }
                @{
                    scenario        = "null excludedActions property"
                    excludedActions = $null
                    expected        = "^(?!.*--deny-settings-excluded-actions).*$"
                }
                @{
                    scenario        = "empty array excludedActions"
                    excludedActions = @()
                    expected        = '--deny-settings-excluded-actions ""'
                }
                @{
                    scenario        = "single item excludedActions"
                    excludedActions = @("mock-action")
                    expected        = '--deny-settings-excluded-actions "mock-action"'
                }
                @{
                    scenario        = "multiple items excludedActions"
                    excludedActions = @("mock-action1", "mock-action2")
                    expected        = '--deny-settings-excluded-actions "mock-action1" "mock-action2"'
                }
            ) {
                param ($scenario, $excludedActions, $expected)
                
                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'             = "targetScope = 'subscription'"
                    'prod.bicepparam'        = "using 'main.bicep'"
                    'deploymentconfig.jsonc' = @{
                        type         = "deploymentStack"
                        denySettings = @{
                            mode            = "denyDelete"
                            excludedActions = $excludedActions
                        }
                    } | ConvertTo-Json
                }
                
                Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
                | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
            }
        }

        # MARK: Stack 'denySettings.excludedPrincipals'
        Context "When handling stack 'denySettings.excludedPrincipals' property" {
            It "Should handle <scenario> correctly" -TestCases @(
                @{
                    scenario = "no excludedPrincipals property"
                    expected = "^(?!.*--deny-settings-excluded-principals).*$"
                }
                @{
                    scenario           = "null excludedPrincipals property"
                    excludedPrincipals = $null
                    expected           = "^(?!.*--deny-settings-excluded-principals).*$"
                }
                @{
                    scenario           = "empty array excludedPrincipals"
                    excludedPrincipals = @()
                    expected           = '--deny-settings-excluded-principals ""'
                }
                @{
                    scenario           = "single item excludedPrincipals"
                    excludedPrincipals = @("mock-principal")
                    expected           = '--deny-settings-excluded-principals "mock-principal"'
                }
                @{
                    scenario           = "multiple items excludedPrincipals"
                    excludedPrincipals = @("mock-principal1", "mock-principal2")
                    expected           = '--deny-settings-excluded-principals "mock-principal1" "mock-principal2"'
                }
            ) {
                param ($scenario, $excludedPrincipals, $expected)
                
                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'             = "targetScope = 'subscription'"
                    'prod.bicepparam'        = "using 'main.bicep'"
                    'deploymentconfig.jsonc' = @{
                        type         = "deploymentStack"
                        denySettings = @{
                            mode               = "denyDelete"
                            excludedPrincipals = $excludedPrincipals
                        }
                    } | ConvertTo-Json
                }
                
                Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
                | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
            }
        }

        # MARK: Stack 'actionOnUnmanage'
        Context "When handling stack 'actionOnUnmanage' property" {
            It "Should handle <scenario> correctly" -TestCases @(
                @{
                    scenario = "no actionOnUnmanage property"
                    expected = "--action-on-unmanage detachAll"
                }
                @{
                    scenario         = "null actionOnUnmanage property"
                    actionOnUnmanage = $null
                    expected         = "--action-on-unmanage detachAll"
                }
                @{
                    scenario         = "resources and resourceGroups is 'delete'"
                    actionOnUnmanage = @{ resources = "delete"; resourceGroups = "delete" }
                    expected         = "--action-on-unmanage deleteAll"
                }
                @{
                    scenario         = "resources is 'delete' but resourceGroups is not 'delete'"
                    actionOnUnmanage = @{ resources = "delete" }
                    expected         = "--action-on-unmanage deleteResources"
                }
            ) {
                param ($scenario, $actionOnUnmanage, $expected)
                
                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'             = "targetScope = 'subscription'"
                    'prod.bicepparam'        = "using 'main.bicep'"
                    'deploymentconfig.jsonc' = @{
                        type             = "deploymentStack"
                        actionOnUnmanage = $actionOnUnmanage
                    } | ConvertTo-Json
                }
                
                Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
                | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
            }

            Context "When scope is 'managementGroup'" {
                It "Should handle <scenario> correctly" -TestCases @(
                    @{
                        scenario         = "resources, resourceGroups and managementGroups is 'delete'"
                        actionOnUnmanage = @{ resources = "delete"; resourceGroups = "delete"; managementGroups = "delete" }
                        expected         = "--action-on-unmanage deleteAll"
                    }
                    @{
                        scenario         = "resources and resourceGroups is 'delete' but managementGroups is not 'delete'"
                        actionOnUnmanage = @{ resources = "delete"; resourceGroups = "delete" }
                        expected         = "--action-on-unmanage deleteResources"
                    }
                    @{
                        scenario         = "resources is 'delete' but resourceGroups is not 'delete'"
                        actionOnUnmanage = @{ resources = "delete" }
                        expected         = "--action-on-unmanage deleteResources"
                    }
                ) {
                    param ($scenario, $actionOnUnmanage, $expected)
                
                    New-FileStructure -Path $testRoot -Structure @{
                        'main.bicep'             = "targetScope = 'managementGroup'"
                        'prod.bicepparam'        = "using 'main.bicep'"
                        'deploymentconfig.jsonc' = @{
                            type              = "deploymentStack"
                            managementGroupId = "mock-mg"
                            actionOnUnmanage  = $actionOnUnmanage
                        } | ConvertTo-Json
                    }
                
                    Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
                    | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
                }
            }
        }

        # MARK: Stack 'tags'
        Context "When handling stack 'tags' property" {
            It "Should handle <scenario> correctly" -TestCases @(
                @{
                    scenario         = "no tags property"
                    deploymentConfig = @{}
                    expected         = '--tags ""'
                }
                @{
                    scenario         = "null tags property"
                    deploymentConfig = @{ tags = $null }
                    expected         = '--tags ""'
                }
                @{
                    scenario         = "empty tags"
                    deploymentConfig = @{ tags = @{} }
                    expected         = '--tags ""'
                }
                @{
                    scenario         = "single tag"
                    deploymentConfig = @{ tags = @{ "key" = "value" } }
                    expected         = "--tags 'key=value'"
                }
                @{
                    scenario         = "multiple tags"
                    deploymentConfig = @{ tags = [ordered]@{ "key1" = "value1"; "key2" = "value2" } }
                    expected         = "--tags 'key1=value1' 'key2=value2'"
                }
            ) {
                param ($scenario, $deploymentConfig, $expected)
                
                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'             = "targetScope = 'subscription'"
                    'prod.bicepparam'        = "using 'main.bicep'"
                    'deploymentconfig.jsonc' = @{
                        type = "deploymentStack"
                    } + $deploymentConfig | ConvertTo-Json
                }
            
                Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
                | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
            }
        }

        # MARK: Stack 'deploymentResourceGroup'
        Context "When handling stack 'deploymentResourceGroup' property" {
            It "Should handle <scenario> correctly" -TestCases @(
                @{
                    scenario         = "no deploymentResourceGroup property"
                    deploymentConfig = @{}
                    expected         = "^(?!.*--deployment-resource-group).*$"
                }
                @{
                    scenario         = "null deploymentResourceGroup"
                    deploymentConfig = @{ deploymentResourceGroup = $null }
                    expected         = "^(?!.*--deployment-resource-group).*$"
                }
                @{
                    scenario         = "empty deploymentResourceGroup"
                    deploymentConfig = @{ deploymentResourceGroup = "" }
                    expected         = "^(?!.*--deployment-resource-group).*$"
                }
                @{
                    scenario         = "non-empty deploymentResourceGroup"
                    deploymentConfig = @{ deploymentResourceGroup = "mock-rg" }
                    expected         = "--deployment-resource-group mock-rg"
                }
            ) {
                param ($scenario, $deploymentConfig, $expected)
                
                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'             = "targetScope = 'subscription'"
                    'prod.bicepparam'        = "using 'main.bicep'"
                    'deploymentconfig.jsonc' = @{
                        type = "deploymentStack"
                    } + $deploymentConfig | ConvertTo-Json
                }
            
                Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
                | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
            }

            # TODO: Not supported yet
            # It "Should fail if 'deploymentResourceGroup' is specified and the scope is 'resourceGroup'" {

            #     New-FileStructure -Path $testRoot -Structure @{
            #         'main.bicep'             = "targetScope = 'resourceGroup'"
            #         'prod.bicepparam'        = "using 'main.bicep'"
            #         'deploymentconfig.jsonc' = @{
            #             type                    = "deploymentStack"
            #             resourceGroupName       = "mock-rg" 
            #             deploymentResourceGroup = "mock-rg"
            #         } | ConvertTo-Json
            #     }

            #     { Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam" }
            #     | Should -Throw "The 'deploymentResourceGroup' property is only supported when the target scope is 'resourceGroup'."
            # }

            # It "Should fail if 'deploymentResourceGroup' is specified and the scope is 'managementGroup'" {

            #     New-FileStructure -Path $testRoot -Structure @{
            #         'main.bicep'             = "targetScope = 'managementGroup'"
            #         'prod.bicepparam'        = "using 'main.bicep'"
            #         'deploymentconfig.jsonc' = @{
            #             type                    = "deploymentStack"
            #             managementGroupId       = "mock-mg" 
            #             deploymentResourceGroup = "mock-rg"
            #         } | ConvertTo-Json
            #     }

            #     { Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam" }
            #     | Should -Throw "The 'deploymentResourceGroup' property is only supported when the target scope is 'resourceGroup'."
            # }
        }

        # MARK: Stack 'deploymentSubscription'
        Context "Handle 'deploymentSubscription' property" {
            It "Should handle <scenario> deploymentSubscription correctly" -TestCases @(
                @{
                    scenario         = "no deploymentSubscription property"
                    deploymentConfig = @{}
                    expected         = "^(?!.*--deployment-resource-group).*$"
                }
                @{
                    scenario         = "null deploymentSubscription"
                    deploymentConfig = @{ deploymentSubscription = $null }
                    expected         = "^(?!.*--deployment-subscription).*$"
                }
                @{
                    scenario         = "empty deploymentSubscription"
                    deploymentConfig = @{ deploymentSubscription = "" }
                    expected         = "^(?!.*--deployment-subscription).*$"
                }
                @{
                    scenario         = "non-empty deploymentSubscription"
                    deploymentConfig = @{ deploymentSubscription = "mock-sub" }
                    expected         = "--deployment-subscription mock-sub"
                }
            ) {
                param ($scenario, $deploymentConfig, $expected)
                
                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'             = "targetScope = 'managementGroup'"
                    'prod.bicepparam'        = "using 'main.bicep'"
                    'deploymentconfig.jsonc' = @{
                        type              = "deploymentStack"
                        managementGroupId = 'mock-mg'
                    } + $deploymentConfig | ConvertTo-Json
                }
            
                Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
                | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
            }

            # TODO: Not supported yet
            # It "Should fail if 'deploymentSubscription' is specified and the scope is 'resourceGroup'" {
            #     New-FileStructure -Path $testRoot -Structure @{
            #         'main.bicep'             = "targetScope = 'resourceGroup'"
            #         'prod.bicepparam'        = "using 'main.bicep'"
            #         'deploymentconfig.jsonc' = @{
            #             type                   = "deploymentStack"
            #             resourceGroupName      = "mock-rg" 
            #             deploymentSubscription = "mock-sub"
            #         } | ConvertTo-Json
            #     }

            #     { Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam" }
            #     | Should -Throw "The 'deploymentSubscription' property is only supported when the target scope is 'managementGroup'."
            # }

            # It "Should fail if 'deploymentResourceGroup' is specified and the scope is 'subscription'" {
            #     New-FileStructure -Path $testRoot -Structure @{
            #         'main.bicep'             = "targetScope = 'subscription'"
            #         'prod.bicepparam'        = "using 'main.bicep'"
            #         'deploymentconfig.jsonc' = @{
            #             type                   = "deploymentStack"
            #             deploymentSubscription = "mock-sub"
            #         } | ConvertTo-Json
            #     }

            #     { Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam" }
            #     | Should -Throw "The 'deploymentSubscription' property is only supported when the target scope is 'managementGroup'."
            # }
        }

        # MARK: Stack 'DeploymentWhatIf'
        Context "Handle 'DeploymentWhatIf' parameter" {
            It "Should handle <scenario> correctly" -TestCases @(
                @{
                    scenario = "no 'DeploymentWhatIf' parameter"
                    expected = "^az stack sub create"
                }
                @{
                    scenario         = "false 'DeploymentWhatIf' parameter"
                    deploymentWhatIf = $false
                    expected         = "^az stack sub create"
                }
                @{
                    scenario         = "true 'DeploymentWhatIf' parameter"
                    deploymentWhatIf = $true
                    expected         = "^az stack sub validate"
                }
            ) {
                param ($scenario, $deploymentWhatIf, $expected)

                New-FileStructure -Path $testRoot -Structure @{
                    'main.bicep'             = "targetScope = 'subscription'"
                    'prod.bicepparam'        = "using 'main.bicep'"
                    'deploymentconfig.jsonc' = @{ type = "deploymentStack" } | ConvertTo-Json
                }

                $deploymentWhatIfParam = @{}
                if ($deploymentWhatIf) {
                    $deploymentWhatIfParam = @{ DeploymentWhatIf = $deploymentWhatIf }
                }

                Resolve-DeploymentConfig @commonParams @deploymentWhatIfParam -DeploymentFilePath "$testRoot/prod.bicepparam"
                | Select-Object -ExpandProperty "AzureCliCommand" | Should -Match $expected
            }
        }
    }

    # MARK: climprconfig.jsonc behavior
    Context "Handle climprconfig.jsonc behavior correctly" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario         = "no climprconfig and no deploymentconfig file"
                climprConfig     = @{}
                deploymentConfig = @{}
                expected         = "westeurope" # Action default
            }
            @{
                scenario         = "climprconfig action default override"
                climprConfig     = @{ bicepDeployment = @{ location = 'swedencentral' } }
                deploymentConfig = @{}
                expected         = "swedencentral"
            }
            @{
                scenario         = "deploymentconfig override action default"
                climprConfig     = @{}
                deploymentConfig = @{ location = 'swedencentral' }
                expected         = "swedencentral"
            }
            @{
                scenario         = "deploymentconfig override climprconfig"
                climprConfig     = @{ bicepDeployment = @{ location = 'eastus' } }
                deploymentConfig = @{ location = 'swedencentral' }
                expected         = "swedencentral"
            }
        ) {
            param ($scenario, $climprConfig, $deploymentConfig, $expected)
            
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'             = "targetScope = 'subscription'"
                'prod.bicepparam'        = "using 'main.bicep'"
                'climprconfig.jsonc'     = $climprConfig | ConvertTo-Json
                'deploymentconfig.jsonc' = $deploymentConfig | ConvertTo-Json
            }

            $result = Resolve-DeploymentConfig @commonParams -DeploymentFilePath "$testRoot/prod.bicepparam"
            $result.Location | Should -BeExactly $expected
        }
    }
}
