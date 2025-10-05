BeforeAll {
    if ((Get-PSResourceRepository -Name PSGallery).Trusted -eq $false) {
        Set-PSResourceRepository -Name PSGallery -Trusted -Confirm:$false
    }
    if (!(Get-PSResource -Name Bicep -ErrorAction Ignore)) {
        Install-PSResource -Name Bicep
    }
    Update-PSResource -Name Bicep
    Import-Module $PSScriptRoot/../DeployBicepHelpers.psm1 -Force
}

Describe "Resolve-ParameterFileTarget" {
    Context "Input handling" {
        Context "When the input is a file path" {
            BeforeAll {
                $script:testRoot = Join-Path $TestDrive 'mock'
                $script:paramFile = Join-Path $testRoot "test.bicepparam"
                New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
            }

            AfterAll {
                Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue -ProgressAction SilentlyContinue
            }

            It "It should return 'main.bicep'" {
                "using 'main.bicep'" | Out-File -Path $paramFile
                Resolve-ParameterFileTarget -Path $paramFile | Should -BeExactly "main.bicep"
            }
        }

        Context "When the input is a string" {
            It "It should return 'main.bicep'" {
                Resolve-ParameterFileTarget -Content "using 'main.bicep'" | Should -BeExactly "main.bicep"
            }
        }
    }

    Context "Whitespace handling" {
        It "Should handle <Scenario>" -TestCases @(
            @{
                Scenario = "statements without spaces"
                Content  = "using'main.bicep'"
                Expected = "main.bicep"
            }
            @{
                Scenario = "leading spaces before using keyword"
                Content  = "  using 'main.bicep'"
                Expected = "main.bicep"
            }
            @{
                Scenario = "whitespace between using and path"
                Content  = "using      'main.bicep'"
                Expected = "main.bicep"
            }
            @{
                Scenario = "whitespace inside path quotes"
                Content  = "using '  main.bicep'"
                Expected = "main.bicep"
            }
        ) {
            param ($Content, $Expected)
            Resolve-ParameterFileTarget -Content $Content | Should -BeExactly $Expected
        }
    }

    Context "Path handling" {
        It "Should handle <Scenario>" -TestCases @(
            @{
                Scenario = "relative path"
                Content  = "using './main.bicep'"
                Expected = "./main.bicep"
            }
            @{
                Scenario = "absolute path"
                Content  = "using '/main.bicep'"
                Expected = "/main.bicep"
            }
            @{
                Scenario = "parent path"
                Content  = "using '../main.bicep'"
                Expected = "../main.bicep"
            }
            @{
                Scenario = "hidden file"
                Content  = "using '.main.bicep'"
                Expected = ".main.bicep"
            }
        ) {
            param ($Content, $Expected)
            Resolve-ParameterFileTarget -Content $Content | Should -BeExactly $Expected
        }
    }

    It "Should handle registry paths" {
        $paths = @(
            @{ Path = "br/public:filepath:tag"; Expected = "br/public:filepath:tag" }
            @{ Path = "br:mcr.microsoft.com/bicep/filepath:tag"; Expected = "br:mcr.microsoft.com/bicep/filepath:tag" }
        )

        foreach ($testCase in $paths) {
            Resolve-ParameterFileTarget -Content "using '$($testCase.Path)'" | 
            Should -BeExactly $testCase.Expected
        }
    }

    It "Should handle extendable parameter files using none keyword" {
        $content = "using none"
        Resolve-ParameterFileTarget -Content $content | Should -BeExactly 'none'
    }
}

Context "Position handling" {
    It "Should handle using statement not on first line" {
        $content = @"
metadata author = 'author'
using 'main.bicep'
"@
        Resolve-ParameterFileTarget -Content $content | Should -BeExactly 'main.bicep'
    }
}
