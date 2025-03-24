# Pester test suite for Remove-BicepComments function
BeforeAll {
    Import-Module $PSScriptRoot/../DeployBicepHelpers.psm1 -Force
}

Describe "Remove-BicepComments Function" {
    Context "Basic Comment Removal" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario = "single-line comment"
                content  = "var example = 1 // This is a comment"
                expected = "var example = 1"
            }
            @{
                scenario = "multi-line comment"
                content  = "var example = 1 /* This is a `nmulti-line comment */ var another = 2"
                expected = "var example = 1  var another = 2"
            }
            @{
                scenario = "multi-line comment on single line"
                content  = "var example =/* This is a multi-line comment */  2"
                expected = "var example =  2"
            }
            @{
                scenario = "empty multi-line comments"
                content  = "var example = 1 /**/ var another = 2"
                expected = "var example = 1  var another = 2"
            }
        ) {
            param ($content, $expected)
            Remove-BicepComments -Content $content
            | Should -BeExactly $expected
        }
    }
    
    Context "String Content Preservation" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario = "preserves comments inside strings"
                content  = @'
var example = 'This is a // not a comment'
var another = 'Multi-line /* not a comment */ still a string'
'@
            }
            @{
                scenario = "handles escaped single quotes inside strings"
                content  = "var example = 'This isn\'t a comment'"
            }
            @{
                scenario = "handles unterminated strings with comment markers"
                content  = "var example = 'Unclosed string with // inside"
            }
            @{
                scenario = "handles escaped characters in strings with comments"
                content  = @'
var example = '\n\t\r // not a comment'
var another = '\n\t\r /* not a comment */'
'@
            }
            @{
                scenario = "handles complex string combinations"
                content  = @'
var example = 'string with \'quote\' and // comment marker'
var another = 'string with /* comment markers */ inside'
'@
            }
            @{
                scenario = "handles inline multi-line strings"
                content  = "var example = '''string wit'h \'quote\' and // comment marker'''"
            }
            @{
                scenario = "handles multi-line strings"
                content  = @'
var example = '''string wit'h \'quote\'
    and // comment marker'''
'@
            }
        ) {
            param ($content)
            Remove-BicepComments -Content $content
            | Should -BeExactly $content
        }
    }

    Context "Whitespace handling" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario = "removes trailing whitespace"
                content  = "var example = 1   "
                expected = "var example = 1"
            }
            @{
                scenario = "handles empty lines and trims"
                content  = "var example = 1`n`nvar another = 2"
                expected = "var example = 1`nvar another = 2"
            }
        ) {
            param ($content, $expected)
            Remove-BicepComments -Content $content
            | Should -BeExactly $expected
        }
    }

    Context "Comment placement" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario = "single-line comment at beginning of file"
                content  = "// This is a comment`nvar example = 1"
                expected = "var example = 1"
            }
            @{
                scenario = "multi-line comment at beginning of file"
                content  = "/* Multi-line comment */`nvar example = 1"
                expected = "var example = 1"
            }
            @{
                scenario = "multi-line comment at end of file"
                content  = "var example = 1 /* comment */"
                expected = "var example = 1"
            }
            @{
                scenario = "multiple multi-line comments on same line"
                content  = "var example = 1 /* first */ var another = 2 /* second */"
                expected = "var example = 1  var another = 2"
            }
            @{
                scenario = "multiple single-line comments"
                content  = "var example = 1 // comment 1`nvar another = 2 // comment 2"
                expected = "var example = 1`nvar another = 2"
            }
            @{
                scenario = "single line comments with special characters"
                content  = "var third = 3 // $#@!%^&*()_+"
                expected = "var third = 3"
            }
            @{
                scenario = "multi-line comments with special characters"
                content  = "var example = 1 /* $#@!%^&*()_+ */ var another = 2"
                expected = "var example = 1  var another = 2"
            }
            @{
                scenario = "single line comments with Unicode characters"
                content  = "var third = 3 // 说明"
                expected = "var third = 3"
            }
            @{
                scenario = "multi-line comments with Unicode characters"
                content  = "var example = 1 /* コメント */ var another = 2"
                expected = "var example = 1  var another = 2"
            }
            @{
                scenario = "comments with newlines"
                content  = "var example = 1 /* comment with`n`nnewlines */ var another = 2"
                expected = "var example = 1  var another = 2"
            }
            @{
                scenario = "unclosed multi-line comment markers"
                content  = "var example = 1 /* unclosed comment"
                expected = "var example = 1"
            }
            @{
                scenario = "inline multi-line comments with single quotes before valid string"
                content  = "var example/* comment with ' single quote */ = 'test'"
                expected = "var example = 'test'"
            }
        ) {
            param ($content, $expected)
            Remove-BicepComments -Content $content
            | Should -BeExactly $expected
        }
    }

    Context "Edge cases" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario = "null input"
                content  = $null
                expected = ""
            }
            @{
                scenario = "empty string input"
                content  = ""
                expected = ""
            }
            @{
                scenario = "whitespace only input"
                content  = "    `n`t`n    "
                expected = ""
            }
            @{
                scenario = "multiple nested-like multi-line comment markers with lazy matching"
                content  = "var example = 1 /* outer /* inner */ var another = 2 */ var third = 3"
                expected = "var example = 1  var another = 2 */ var third = 3"
            }
            @{
                scenario = "indentation after removing comments"
                content  = "    var example = 1 // comment`n        var another = 2 /* comment */"
                expected = "    var example = 1`n        var another = 2"
            }
        ) {
            param ($content, $expected)
            Remove-BicepComments -Content $content
            | Should -BeExactly $expected
        }
    }
}