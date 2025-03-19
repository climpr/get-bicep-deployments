# Pester test suite for Remove-BicepComments function
BeforeAll {
    Import-Module $PSScriptRoot/../support-functions.psm1 -Force
    Import-Module Pester
}

Describe "Remove-BicepComments Function" {
    Context "Basic Comment Removal" {
        It "Removes single-line comments" {
            $content = "var example = 1 // This is a comment"
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example = 1"
        }
        
        It "Removes multi-line comments" {
            $content = @'
var example = 1 /* This is a 
multi-line comment */ var another = 2
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example = 1  var another = 2"
        }

        It "Removes multi-line comments on single line" {
            $content = "var example =/* This is a multi-line comment */  2"
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example =  2"
        }

        It "Handles empty multi-line comments" {
            $content = "var example = 1 /**/ var another = 2"
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example = 1  var another = 2"
        }
    }

    Context "String Content Preservation" {
        It "Preserves comments inside strings" {
            $content = @'
var example = 'This is a // not a comment'
var another = 'Multi-line /* not a comment */ still a string'
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly $content
        }

        It "Handles escaped single quotes inside strings" {
            $content = "var example = 'This isn\'t a comment'"
            Remove-BicepComments -Content $content
            | Should -BeExactly $content
        }

        It "Handles unterminated strings with comment markers" {
            $content = "var example = 'Unclosed string with // inside"
            Remove-BicepComments -Content $content
            | Should -BeExactly $content
        }

        It "Handles escaped characters in strings with comments" {
            $content = @'
var example = '\n\t\r // not a comment'
var another = '\n\t\r /* not a comment */'
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly $content
        }

        It "Handles complex string combinations" {
            $content = @'
var example = 'string with \'quote\' and // comment marker'
var another = 'string with /* comment markers */ inside'
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly $content
        }
    }

    Context "Whitespace Handling" {
        It "Removes trailing whitespace" {
            $content = "var example = 1   "
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example = 1"
        }

        It "Handles empty lines and trims properly" {
            $content = @'
var example = 1   

var another = 2  
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly @'
var example = 1
var another = 2
'@
        }
    }

    Context "Comment Placement" {
        It "Handles single-line comment at beginning of file" {
            $content = @'
// This is a comment
var example = 1
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example = 1"
        }

        It "Handles multi-line comment at beginning of file" {
            $content = @'
/* Multi-line comment */
var example = 1
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example = 1"
        }

        It "Handles multi-line comment at end of file" {
            $content = "var example = 1 /* comment */"
            Remove-BicepComments -Content $content 
            | Should -BeExactly "var example = 1"
        }

        It "Handles multiple multi-line comments on same line" {
            $content = "var example = 1 /* first */ var another = 2 /* second */"
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example = 1  var another = 2"
        }

        It "Handles multiple single-line comments" {
            $content = @'
var example = 1 // comment 1
var another = 2 // comment 2
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly @'
var example = 1
var another = 2
'@
        }

        It "Handles comments with special characters" {
            $content = @'
var example = 1 /* $#@!%^&*()_+ */ var another = 2
var third = 3 // $#@!%^&*()_+
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly @'
var example = 1  var another = 2
var third = 3
'@
        }

        It "Handles comments with Unicode characters" {
            $content = @'
var example = 1 /* コメント */ var another = 2
var third = 3 // 说明
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly @'
var example = 1  var another = 2
var third = 3
'@
        }

        It "Handles comments with newlines" {
            $content = @'
var example = 1 /* comment with

newlines */ var another = 2
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example = 1  var another = 2"
        }

        It "Handles unclosed multi-line comment markers" {
            $content = "var example = 1 /* unclosed comment"
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example = 1"
        }

        It "Handled inline multi-line comments with single quotes before valid string" {
            $content = "var example/* comment with ' single quote */ = 'test'"
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example = 'test'"
        }
    }

    Context "Edge Cases" {
        It "Handles null input gracefully" {
            { Remove-BicepComments -Content $null } | Should -Not -Throw
        }

        It "Handles empty string input" {
            Remove-BicepComments -Content "" | Should -BeExactly ""
        }

        It "Handles whitespace-only input" {
            Remove-BicepComments -Content "    `n`t`n    " | Should -BeExactly ""
        }

        It "Handles multiple nested-like multi-line comment markers with lazy matching" {
            $content = "var example = 1 /* outer /* inner */ var another = 2 */ var third = 3"
            Remove-BicepComments -Content $content
            | Should -BeExactly "var example = 1  var another = 2 */ var third = 3"
        }

        It "Preserves indentation after removing comments" {
            $content = @'
    var example = 1 // comment
        var another = 2 /* comment */
'@
            Remove-BicepComments -Content $content
            | Should -BeExactly @'
    var example = 1
        var another = 2
'@
        }
    }
}