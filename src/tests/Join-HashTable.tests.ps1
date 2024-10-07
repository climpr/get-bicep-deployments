Import-Module $PSScriptRoot/../support-functions.psm1 -Force

Describe "Join-HashTable" {
    Context "When both inputs are empty hashtables" {
        BeforeAll {
            $script:result = Join-Hashtable -Hashtable1 @{} -Hashtable2 @{}
        }
        
        It "It should return an empty hashtable" {
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -HaveCount 0
        }
    }

    Context "When the first hashtable is empty" {
        BeforeAll {
            $script:result = Join-Hashtable -Hashtable1 @{} -Hashtable2 @{ key1 = "value1" }
        }

        It "It should return a hashtable equal to the second hashtable" {
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -HaveCount 1
            $result.key1 | Should -Be "value1"
        }
    }
    
    Context "When the second hashtable is empty" {
        BeforeAll {
            $script:result = Join-Hashtable -Hashtable1 @{ key1 = "value1" } -Hashtable2 @{}
        }

        It "It should return a hashtable equal to the first hashtable" {
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -HaveCount 1
            $result.key1 | Should -Be "value1"
        }
    }
    
    Context "When the hashtables are equal" {
        BeforeAll {
            $script:result = Join-Hashtable -Hashtable1 @{ key1 = "value1" } -Hashtable2 @{ key1 = "value1" }
        }

        It "It should return a hashtable equal to one of the hashtables" {
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -HaveCount 1
            $result.key1 | Should -Be "value1"
        }
    }
    
    Context "When the hashtables are not equal and have different keys" {
        BeforeAll {
            $script:result = Join-Hashtable -Hashtable1 @{ key1 = "value1" } -Hashtable2 @{ key2 = "value2" }
        }
        
        It "It should return a hashtable with values from both input hashtables" {
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -HaveCount 2
            $result.key1 | Should -Be "value1"
            $result.key2 | Should -Be "value2"
        }
    }
    
    Context "When the hashtables are not equal and have the same key but different values" {
        BeforeAll {
            $script:result = Join-Hashtable -Hashtable1 @{ key1 = "value1" } -Hashtable2 @{ key1 = "value2" }
        }

        It "It should return a hashtable with values from the second input hashtable" {
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -HaveCount 1
            $result.key1 | Should -Be "value2"
        }
    }
    
    Context "When the hashtables are nested" {
        BeforeAll {
            $script:result = Join-Hashtable `
                -Hashtable1 @{
                key1 = "value1"
                key2 = @{
                    subKey1 = "subValue1"
                    subKey2 = "subValue2"
                    subKey3 = "subValue3"
                }
            } `
                -Hashtable2 @{
                key1 = "value2"
                key2 = @{
                    subKey1 = "subValue1"
                    subKey2 = "otherValue"
                }
                key3 = @{
                    subKey1 = "subValue1"
                }
            }
        }

        It "It should return a deep merged hashtable" {
            $result | Should -BeOfType [hashtable]
            $result.key1.Keys | Should -HaveCount 1
            $result.key1 | Should -Be "value2"
            $result.key2.Keys | Should -HaveCount 3
            $result.key2.subKey1 | Should -Be "subValue1"
            $result.key2.subKey2 | Should -Be "otherValue"
            $result.key2.subKey3 | Should -Be "subValue3"
            $result.key3.Keys | Should -HaveCount 1
            $result.key3.subKey1 | Should -Be "subValue1"
        }
    }
}
