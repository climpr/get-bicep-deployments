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

Describe "Get-BicepFileReferences" {
    BeforeEach {
        # Create mock root directory
        $script:testRoot = Join-Path $TestDrive 'mock'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue -ProgressAction SilentlyContinue
    }

    Context "When processing local file references" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario   = "no module reference"
                expected   = @('main.bicep')
                entryPoint = 'main.bicep'
                mock       = @{
                    'main.bicep' = ""
                }
            }
            @{
                scenario   = "single module reference"
                expected   = @('main.bicep', 'modules/storage.bicep')
                entryPoint = 'main.bicep'
                mock       = @{
                    'main.bicep' = "module storage 'modules/storage.bicep' = { name: 'storage' }"
                    'modules'    = @{
                        'storage.bicep' = ""
                    }
                }
            }
            @{
                scenario   = "multi module reference"
                expected   = @('main.bicep', 'modules/storage.bicep', 'modules/keyvault.bicep')
                entryPoint = 'main.bicep'
                mock       = @{
                    'main.bicep' = "module storage 'modules/storage.bicep' = { name: 'storage' }`nmodule keyvault 'modules/keyvault.bicep' = { name: 'keyvault' }"
                    'modules'    = @{
                        'storage.bicep'  = ""
                        'keyvault.bicep' = ""
                    }
                }
            }
            @{
                scenario   = "nested nested module reference"
                expected   = @('main.bicep', 'modules/storage.bicep', 'modules/rbac/role-assignment.bicep')
                entryPoint = 'main.bicep'
                mock       = @{
                    'main.bicep' = "module storage 'modules/storage.bicep' = { name: 'storage' }"
                    'modules'    = @{
                        'storage.bicep' = "module rbac 'rbac/role-assignment.bicep' = { name: 'rbac' }"
                        'rbac'          = @{
                            'role-assignment.bicep' = ""
                        }
                    }
                }
            }
        ) {
            param ($mock, $expected)
            # Create mock deployments
            New-FileStructure -Path $testRoot -Structure $mock

            # Resolve relative paths
            $relativeExpectedPaths = foreach ($item in $expected) {
                $fullPath = Join-Path -Path $testRoot -ChildPath $item
                if (Test-Path -Path $fullPath) { Resolve-Path -Relative $fullPath }
                else { $item }
            }

            # Run script
            $result = Get-BicepFileReferences -Path $entryPoint -ParentPath $testRoot
            
            # Assert
            $result | Should -HaveCount $expected.Count
            $result | Should -BeIn $relativeExpectedPaths
        }
    }

    Context "When processing remote references" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario   = "Azure Container Registry (ACR) references"
                expected   = @(
                    'main.bicep'
                    'br:myregistry.azurecr.io/module:v1'
                    'br:myregistry.azurecr.io/module@sha256:abcdef1234567890'
                    'br:myregistry.azurecr.io/folder/module:v2'
                    'br:myregistry.azurecr.io/module:latest'
                    'br/alias:module:v1'
                    'br/alias:folder/module:v1'
                )
                entryPoint = 'main.bicep'
                mock       = @{
                    'main.bicep' = @(
                        "module module1 'br:myregistry.azurecr.io/module:v1' = { name: 'module1' }"
                        "module module2 'br:myregistry.azurecr.io/module@sha256:abcdef1234567890' = { name: 'module2' }"
                        "module module3 'br:myregistry.azurecr.io/folder/module:v2' = { name: 'module3' }"
                        "module module4 'br:myregistry.azurecr.io/module:latest' = { name: 'module4' }"
                        "module module5 'br/alias:module:v1' = { name: 'module5' }"
                        "module module6 'br/alias:folder/module:v1' = { name: 'module6' }"
                    ) -join "`n"
                }
            }
            @{
                scenario   = "Template Specs (TS) references"
                expected   = @(
                    'main.bicep'
                    'ts:subid/rg/module:v1'
                    'ts/alias:module:v1'
                )
                entryPoint = 'main.bicep'
                mock       = @{
                    'main.bicep' = @(
                        "module module1 'ts:subid/rg/module:v1' = { name: 'module1' }"
                        "module module2 'ts/alias:module:v1' = { name: 'module2' }"
                    ) -join "`n"
                }
            }
        ) {
            param ($mock, $expected)
            # Create mock deployments
            New-FileStructure -Path $testRoot -Structure $mock

            # Resolve relative paths
            $relativeExpectedPaths = foreach ($item in $expected) {
                $fullPath = Join-Path -Path $testRoot -ChildPath $item
                if (Test-Path -Path $fullPath) { Resolve-Path -Relative $fullPath }
                else { $item }
            }

            # Run script
            $result = Get-BicepFileReferences -Path $entryPoint -ParentPath $testRoot
            
            # Assert
            $result | Should -HaveCount $expected.Count
            $result | Should -BeIn $relativeExpectedPaths
        }
    }

    Context "When processing function references" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario   = "loadFileAsBase64() reference"
                expected   = @('main.bicep', 'file.txt')
                entryPoint = 'main.bicep'
                mock       = @{
                    'main.bicep' = "var content = loadFileAsBase64('file.txt')"
                    'file.txt'   = ""
                }
            }
            @{
                scenario   = "loadJsonContent() reference"
                expected   = @('main.bicep', 'file.json')
                entryPoint = 'main.bicep'
                mock       = @{
                    'main.bicep' = "var content = loadJsonContent('file.json')"
                    'file.json'  = ""
                }
            }
            @{
                scenario   = "loadYamlContent() reference"
                expected   = @('main.bicep', 'file.yaml')
                entryPoint = 'main.bicep'
                mock       = @{
                    'main.bicep' = "var content = loadYamlContent('file.yaml')"
                    'file.yaml'  = ""
                }
            }
            @{
                scenario   = "loadTextContent() reference"
                expected   = @('main.bicep', 'file.txt')
                entryPoint = 'main.bicep'
                mock       = @{
                    'main.bicep' = "var content = loadTextContent('file.txt')"
                    'file.txt'   = ""
                }
            }
        ) {
            param ($mock, $expected)
            # Create mock deployments
            New-FileStructure -Path $testRoot -Structure $mock

            # Resolve relative paths
            $relativeExpectedPaths = foreach ($item in $expected) {
                $fullPath = Join-Path -Path $testRoot -ChildPath $item
                if (Test-Path -Path $fullPath) { Resolve-Path -Relative $fullPath }
                else { $item }
            }

            # Run script
            $result = Get-BicepFileReferences -Path $entryPoint -ParentPath $testRoot
            
            # Assert
            $result | Should -HaveCount $expected.Count
            $result | Should -BeIn $relativeExpectedPaths
        }
    }

    Context "When processing parameter file references" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario   = "local template parameter file reference"
                expected   = @('main.bicep', 'main.bicepparam')
                entryPoint = 'main.bicepparam'
                mock       = @{
                    'main.bicep'      = ""
                    'main.bicepparam' = "using 'main.bicep'"
                }
            }
            @{
                scenario   = "remote template parameter file reference"
                expected   = @('main.bicepparam', 'br/alias:module:v1')
                entryPoint = 'main.bicepparam'
                mock       = @{
                    'main.bicepparam' = "using 'br/alias:module:v1'"
                }
            }
            @{
                scenario   = "extendable parameter file reference"
                expected   = @('main.bicep', 'root.bicepparam', 'leaf.bicepparam')
                entryPoint = 'leaf.bicepparam'
                mock       = @{
                    'main.bicep'      = ""
                    'root.bicepparam' = "using none"
                    'leaf.bicepparam' = @(
                        "using 'main.bicep'"
                        "extends 'root.bicepparam'"
                    ) -join "`n"
                }
            }
        ) {
            param ($mock, $expected)
            # Create mock deployments
            New-FileStructure -Path $testRoot -Structure $mock

            # Resolve relative paths
            $relativeExpectedPaths = foreach ($item in $expected) {
                $fullPath = Join-Path -Path $testRoot -ChildPath $item
                if (Test-Path -Path $fullPath) { Resolve-Path -Relative $fullPath }
                else { $item }
            }

            # Run script
            $result = Get-BicepFileReferences -Path $entryPoint -ParentPath $testRoot
            
            # Assert
            $result | Should -HaveCount $expected.Count
            $result | Should -BeIn $relativeExpectedPaths
        }
    }
}