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

Describe "Resolve-TemplateDeploymentScope" {
    BeforeEach {
        # Create mock root directory
        $script:testRoot = Join-Path $TestDrive 'mock'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue -ProgressAction SilentlyContinue
    }

    Context "Local template scope resolution" {
        It "Should resolve <expected> scope" -TestCases @(
            @{
                content  = ""
                config   = @{ resourceGroupName = 'mock-rg' }
                expected = 'resourceGroup'
            }
            @{
                content  = "targetScope = 'resourceGroup'"
                config   = @{ resourceGroupName = 'mock-rg' }
                expected = 'resourceGroup'
            }
            @{
                content  = "targetScope = 'subscription'"
                config   = @{}
                expected = 'subscription'
            }
            @{
                content  = "targetScope = 'managementGroup'"
                config   = @{ managementGroupId = 'mock-mg' }
                expected = 'managementGroup'
            }
            @{
                content  = "targetScope = 'tenant'"
                config   = @{}
                expected = 'tenant'
            }
        ) {
            param($content, $config, $expected)
            
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'      = $content
                'prod.bicepparam' = "using 'main.bicep'"
            }

            Resolve-TemplateDeploymentScope -DeploymentFilePath "$testRoot/prod.bicepparam" -DeploymentConfig $config
            | Should -BeExactly $expected
        }
    }

    Context "DeploymentConfig validation" {
        It "Should throw when <scope> scope is specified without <required> in deploymentconfig.jsonc" -TestCases @(
            @{
                scope         = 'resourceGroup'
                content       = ""
                required      = 'resourceGroupName'
                expectedError = "*Target scope is resourceGroup, but resourceGroupName property is not present*"
            }
            @{
                scope         = 'managementGroup'
                content       = "targetScope = 'managementGroup'"
                required      = 'managementGroupId'
                expectedError = "*Target scope is managementGroup, but managementGroupId property is not present*"
            }
        ) {
            param($content, $expectedError)

            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'      = $content
                'prod.bicepparam' = "using 'main.bicep'"
            }

            { Resolve-TemplateDeploymentScope -DeploymentFilePath "$testRoot/prod.bicepparam" -DeploymentConfig @{} } | Should -Throw $expectedError
        }
    }

    Context "Keyword position validation" {
        It "Should resolve subscription scope" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'      = "metadata author = 'author'`ntargetScope = 'subscription'"
                'prod.bicepparam' = "metadata author = 'author'`nusing 'main.bicep'"
            }

            Resolve-TemplateDeploymentScope -DeploymentFilePath "$testRoot/prod.bicepparam" -DeploymentConfig @{}
            | Should -BeExactly 'subscription'
        }
    }

    Context "Input file types" {
        It "Should resolve subscription scope for .bicep file" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep' = "targetScope = 'subscription'"
            }

            Resolve-TemplateDeploymentScope -DeploymentFilePath "$testRoot/main.bicep" -DeploymentConfig @{}
            | Should -BeExactly 'subscription'
        }
        
        It "Should resolve subscription scope for .bicepparam file" {
            New-FileStructure -Path $testRoot -Structure @{
                'main.bicep'      = "metadata author = 'author'`ntargetScope = 'subscription'"
                'prod.bicepparam' = "metadata author = 'author'`nusing 'main.bicep'"
            }

            Resolve-TemplateDeploymentScope -DeploymentFilePath "$testRoot/prod.bicepparam" -DeploymentConfig @{}
            | Should -BeExactly 'subscription'
        }
    }
}
