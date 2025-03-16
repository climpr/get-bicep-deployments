# Pester test suite for Remove-BicepComments function
BeforeAll {
    Import-Module $PSScriptRoot/../support-functions.psm1 -Force
    Import-Module Pester
}

Describe "Remove-BicepComments Function" {
    It "Removes single-line comments" {
        $bicepContent = @'
var example = 1 // This is a comment
'@
        $expected = @'
var example = 1
'@
        $result = Remove-BicepComments -Content $bicepContent
        $result | Should -BeExactly $expected
    }
    
    It "Removes multi-line comments" {
        $bicepContent = @'
var example = 1 /* This is a 
multi-line comment */ var another = 2
'@
        $expected = @'
var example = 1  var another = 2
'@
        $result = Remove-BicepComments -Content $bicepContent
        $result | Should -BeExactly $expected
    }
    
    It "Removes multi-line comments on single line" {
        $bicepContent = @'
var example =/* This is a multi-line comment */  2
'@
        $expected = @'
var example =  2
'@
        $result = Remove-BicepComments -Content $bicepContent
        $result | Should -BeExactly $expected
    }
    
    It "Preserves comments inside strings" {
        $bicepContent = @'
var example = 'This is a // not a comment'
var another = 'Multi-line /* not a comment */ still a string'
'@
        $expected = @'
var example = 'This is a // not a comment'
var another = 'Multi-line /* not a comment */ still a string'
'@
        $result = Remove-BicepComments -Content $bicepContent
        $result | Should -BeExactly $expected
    }
    
    It "Removes trailing whitespace" {
        $bicepContent = @'
var example = 1    
'@
        $expected = @'
var example = 1
'@
        $result = Remove-BicepComments -Content $bicepContent
        $result | Should -BeExactly $expected
    }
    
    It "Handles empty lines and trims properly" {
        $bicepContent = @'
var example = 1   

var another = 2  
'@
        $expected = @'
var example = 1

var another = 2
'@
        $result = Remove-BicepComments -Content $bicepContent
        $result | Should -BeExactly $expected
    }

    It "Handles single-quotes inside comments properly" {
        $bicepContent = @'
var example = 1   
// comment with 'single quote

var another = 'string'
'@
        $expected = @'
var example = 1

var another = 'string'
'@
        $result = Remove-BicepComments -Content $bicepContent
        $result | Should -BeExactly $expected
    }

    It "Handles removes double or multiple empty lines" {
        $bicepContent = @'
var example = 1


var another = 'string'




var another2 = 'string2'
'@
        $expected = @'
var example = 1

var another = 'string'

var another2 = 'string2'
'@
        $result = Remove-BicepComments -Content $bicepContent
        $result | Should -BeExactly $expected
    }
    
    It "Handles a mix of all cases" {
        $bicepContent = @'
/* Multi-line with ' single quote
 and leading space and 'quoted string' comment */

var example = 1 // Inline comment 

    var another = 2  
'@
        $expected = @'
var example = 1

    var another = 2
'@
        $result = Remove-BicepComments -Content $bicepContent
        $result | Should -BeExactly $expected
    }
}
