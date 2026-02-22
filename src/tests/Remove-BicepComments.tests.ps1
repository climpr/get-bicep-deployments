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

    Context "Multiline Interpolated Strings (Bicep v0.40.2+)" {
        It "Should handle <scenario> correctly" -TestCases @(
            @{
                scenario = "basic multiline interpolated string with single dollar"
                content  = @'
var message = $'''
Hello, this is
a multiline string
with ${variable}'''
'@
                expected = @'
var message = $'''
Hello, this is
a multiline string
with ${variable}'''
'@
            }
            @{
                scenario = "multiline interpolated string on single line"
                content  = @'
var message = $'''hello ${world}'''
'@
                expected = @'
var message = $'''hello ${world}'''
'@
            }
            @{
                scenario = "multiline interpolated string with comment after closing delimiter"
                content  = "var message = $'''hello''' // this is a comment"
                expected = "var message = $'''hello'''"
            }
            @{
                scenario = "escaped dollars in multiline string"
                content  = @'
var message = $$'''
Price: $$100
Not interpolated: $${var}'''
'@
                expected = @'
var message = $$'''
Price: $$100
Not interpolated: $${var}'''
'@
            }
            @{
                scenario = "double dollar escape on single line"
                content  = "var message = `$`$'''cost is `$`$50'''"
                expected = "var message = `$`$'''cost is `$`$50'''"
            }
            @{
                scenario = "preserves comments inside multiline interpolated string"
                content  = @'
var documentation = $'''
This is code:
var x = 1 // not a comment
/* also not */ a comment
'''
'@
                expected = @'
var documentation = $'''
This is code:
var x = 1 // not a comment
/* also not */ a comment
'''
'@
            }
            @{
                scenario = "multiline interpolated string followed by code with comment"
                content  = "var str1 = $'''test''' var str2 = $'''test2''' // comment"
                expected = "var str1 = $'''test''' var str2 = $'''test2'''"
            }
            @{
                scenario = "nested quotes in multiline interpolated string"
                content  = @'
var quoted = $'''
This has 'single quotes'
and "double quotes" inside'''
'@
                expected = @'
var quoted = $'''
This has 'single quotes'
and "double quotes" inside'''
'@
            }
            @{
                scenario = "multiline interpolated string with backslashes"
                content  = @'
var paths = $'''
/path/to/file
C:\Windows\System32'''
'@
                expected = @'
var paths = $'''
/path/to/file
C:\Windows\System32'''
'@
            }
            @{
                scenario = "multiline string followed by interpolated multiline string"
                content  = @'
var plain = '''no interpolation'''
var interpolated = $'''with ${interpolation}'''
'@
                expected = @'
var plain = '''no interpolation'''
var interpolated = $'''with ${interpolation}'''
'@
            }
            @{
                scenario = "dollar sign without triple quotes (not interpolated)"
                content  = "var msg = $'not interpolated'"
                expected = "var msg = $'not interpolated'"
            }
            @{
                scenario = "single-line comment after first multiline string removes remaining content"
                content  = "var str1 = $'''test''' // comment in middle var str2 = $'''test2'''"
                expected = "var str1 = $'''test'''"
            }
            @{
                scenario = "multi-line comment between two multiline interpolated strings"
                content  = "var str1 = $'''test''' /* comment between */ var str2 = $'''test2'''"
                expected = "var str1 = $'''test'''  var str2 = $'''test2'''"
            }
            @{
                scenario = "complex scenario with multiline string before, comment, and string after"
                content  = @'
var config1 = $'''
config1: value1
''' // setup comment var config2 = $'''config2: value2'''
'@
                expected = @'
var config1 = $'''
config1: value1
'''
'@
            }
            @{
                scenario = "multiple alternating strings and comments"
                content  = "var a = $'''first''' // comment1 var b = $'''second''' /* comment2 */ var c = $'''third'''"
                expected = "var a = $'''first'''"
            }

        ) {
            param ($content, $expected)
            Remove-BicepComments -Content $content
            | Should -BeExactly $expected
        }
    }
}