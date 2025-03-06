# Pester test suite for Remove-BicepComments function

Import-Module Pester

Describe "Remove-BicepComments Function" {
    BeforeAll {
        # Define the function under test (mockup example)
        function Remove-BicepComments {
            param ([string]$Content)
            
            # Preserve strings before removing comments
            $stringPattern = "'([^']*)'"
            $strings = @{}
            $Content = $Content -replace $stringPattern, {
                $key = "__STRING$($strings.Count)__"
                $strings[$key] = $_
                return $key
            }
            
            # Remove comments
            $Content = $Content -replace "//.*", ""  # Single-line comments
            $Content = $Content -replace "/\*([\s\S]*?)\*/", ""  # Multi-line comments
            
            # Restore strings
            foreach ($key in $strings.Keys) {
                $Content = $Content -replace [regex]::Escape($key), $strings[$key]
            }
            
            # Trim leading/trailing whitespace for each line
            $Content = ($Content -split "`r?`n" | ForEach-Object { $_.Trim() }) -join "`n"
            
            # Replace multiple blank lines with a single blank line outside of strings
            $Content = $Content -replace "(\n{2,})", "`n"
            
            # Remove leading and trailing blank lines
            $Content = $Content -replace "^(\n)+|(\n)+$", ""
            
            return $Content
        }
    }
    
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
    
    It "Removes leading whitespace" {
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
    
    It "Handles a mix of all cases" {
        $bicepContent = @'
/* Multi-line
comment */

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
