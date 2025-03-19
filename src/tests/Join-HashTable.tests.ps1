BeforeAll {
    Import-Module $PSScriptRoot/../support-functions.psm1 -Force
}

Describe "Join-HashTable" {
    Context "Basic hashtable operations" {
        It "Should handle <Scenario>" -TestCases @(
            @{
                Scenario       = "empty hashtables"
                Hash1          = @{}
                Hash2          = @{}
                ExpectedCount  = 0
                ExpectedValues = @{}
            }
            @{
                Scenario       = "first hashtable empty"
                Hash1          = @{}
                Hash2          = @{ key1 = "value1" }
                ExpectedCount  = 1
                ExpectedValues = @{ key1 = "value1" }
            }
            @{
                Scenario       = "second hashtable empty"
                Hash1          = @{ key1 = "value1" }
                Hash2          = @{}
                ExpectedCount  = 1
                ExpectedValues = @{ key1 = "value1" }
            }
            @{
                Scenario       = "equal hashtables"
                Hash1          = @{ key1 = "value1" }
                Hash2          = @{ key1 = "value1" }
                ExpectedCount  = 1
                ExpectedValues = @{ key1 = "value1" }
            }
            @{
                Scenario       = "different keys"
                Hash1          = @{ key1 = "value1" }
                Hash2          = @{ key2 = "value2" }
                ExpectedCount  = 2
                ExpectedValues = @{ key1 = "value1"; key2 = "value2" }
            }
            @{
                Scenario       = "same key different values"
                Hash1          = @{ key1 = "value1" }
                Hash2          = @{ key1 = "value2" }
                ExpectedCount  = 1
                ExpectedValues = @{ key1 = "value2" }
            }
        ) {
            param ($Hash1, $Hash2, $ExpectedCount, $ExpectedValues)
            
            $result = Join-Hashtable -Hashtable1 $Hash1 -Hashtable2 $Hash2
            
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -HaveCount $ExpectedCount
            
            foreach ($key in $ExpectedValues.Keys) {
                $result[$key] | Should -Be $ExpectedValues[$key]
            }
        }
    }
    
    Context "Nested hashtable operations" {
        It "Should properly merge nested hashtables" {
            $hash1 = @{
                key1 = "value1"
                key2 = @{
                    subKey1 = "subValue1"
                    subKey2 = "subValue2"
                    subKey3 = "subValue3"
                }
            }
            
            $hash2 = @{
                key1 = "value2"
                key2 = @{
                    subKey1 = "subValue1"
                    subKey2 = "otherValue"
                }
                key3 = @{
                    subKey1 = "subValue1"
                }
            }
            
            $result = Join-Hashtable -Hashtable1 $hash1 -Hashtable2 $hash2
            
            # Verify structure
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -HaveCount 3
            
            # Verify top-level values
            $result.key1 | Should -Be "value2"
            
            # Verify nested structures
            $result.key2.Keys | Should -HaveCount 3
            $result.key2.subKey1 | Should -Be "subValue1"
            $result.key2.subKey2 | Should -Be "otherValue"
            $result.key2.subKey3 | Should -Be "subValue3"
            
            $result.key3.Keys | Should -HaveCount 1
            $result.key3.subKey1 | Should -Be "subValue1"
        }
    }
}
