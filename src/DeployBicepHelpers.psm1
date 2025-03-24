#region Private helper functions
function Join-HashTable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [hashtable]
        $Hashtable1 = @{},
        
        [Parameter(Mandatory = $false)]
        [hashtable]
        $Hashtable2 = @{}
    )

    #* Null handling
    $Hashtable1 = $Hashtable1.Keys.Count -eq 0 ? @{} : $Hashtable1
    $Hashtable2 = $Hashtable2.Keys.Count -eq 0 ? @{} : $Hashtable2

    #* Needed for nested enumeration
    $hashtable1Clone = $Hashtable1.Clone()
    
    foreach ($key in $hashtable1Clone.Keys) {
        if ($key -in $hashtable2.Keys) {
            if ($hashtable1Clone[$key] -is [hashtable] -and $hashtable2[$key] -is [hashtable]) {
                $Hashtable2[$key] = Join-HashTable -Hashtable1 $hashtable1Clone[$key] -Hashtable2 $Hashtable2[$key]
            }
            elseif ($hashtable1Clone[$key] -is [array] -and $hashtable2[$key] -is [array]) {
                foreach ($item in $hashtable1Clone[$key]) {
                    if ($hashtable2[$key] -notcontains $item) {
                        $hashtable2[$key] += $item
                    }
                }
            }
        }
        else {
            $Hashtable2[$key] = $hashtable1Clone[$key]
        }
    }
    
    return $Hashtable2
}

function Remove-BicepComments {
    param ([string]$Content)
    $resultLines = @()

    # Normalize line endings to Unix style for consistency
    $Content = $Content -replace "`r`n", "`n"

    $lines = $Content -split "`n"
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        
        # Skip empty or whitespace-only lines
        if ($line -match "^\s*$") {
            continue
        }

        # Iterate through characters in the line
        for ($j = 0; $j -lt $line.Length; $j++) {
            $char = $line[$j]

            if ($char -eq "'") {
                # Check for multi-line string (''' ... ''')
                if ($j -lt $line.Length - 2 -and $line[$j + 1] -eq "'" -and $line[$j + 2] -eq "'") {
                    $j = $j + 2
                    $prefixBeforeString = $line.Substring(0, $j)
                    $remainingLine = $line.Substring($j)

                    $multilineEndMatch = $null
                    while ($i -lt $lines.Count) {
                        $multilineEndMatch = [regex]::Match($remainingLine, "'''")
                        
                        if ($multilineEndMatch.Success -and $multilineEndMatch.Index -gt 0) {
                            # String ends within this line
                            $line = $prefixBeforeString + $remainingLine.Substring(0, $multilineEndMatch.Index + 3)
                            # Reset j to continue checking after the string
                            $j = $prefixBeforeString.Length + $multilineEndMatch.Index + 2
                            break
                        }
                        else {
                            # String spans multiple lines, continue reading
                            $i++
                            if ($i -lt $lines.Count) {
                                $remainingLine += "`n" + $lines[$i]
                            }
                        }
                    }

                    # If string never closed, keep everything after '''
                    if (-not $multilineEndMatch.Success) {
                        $line = $prefixBeforeString + $remainingLine
                        break
                    }
                    continue
                }

                # Check if the quote is escaped (preceded by an odd number of backslashes)
                $escapeCount = 0
                $prevIndex = $j - 1
                while ($prevIndex -ge 0 -and $line[$prevIndex] -eq "\") {
                    $escapeCount++
                    $prevIndex--
                }
                
                if ($escapeCount % 2 -eq 0) {
                    # Entering a string literal
                    $j++
                    while ($j -lt $line.Length) {
                        $char = $line[$j]
                        
                        # Check for unescaped closing quote
                        $escapeCount = 0
                        $prevIndex = $j - 1
                        while ($prevIndex -ge 0 -and $line[$prevIndex] -eq "\") {
                            $escapeCount++
                            $prevIndex--
                        }
            
                        if ($char -eq "'" -and $escapeCount % 2 -eq 0) {
                            # String literal ends
                            break
                        }
                        $j++
                    }
                }
            }
            elseif ($char -eq "/") {
                # Check for single-line comment (//)
                if ($j -lt $line.Length - 1 -and $line[$j + 1] -eq "/") {
                    $line = $line.Substring(0, $j).TrimEnd()
                    break
                }
                # Check for multi-line comment (/* ... */)
                elseif ($j -lt $line.Length - 1 -and $line[$j + 1] -eq "*") {
                    $prefixBeforeComment = $line.Substring(0, $j)
                    $remainingLine = $line.Substring($j)

                    $multilineEndMatch = $null
                    while ($i -lt $lines.Count) {
                        $multilineEndMatch = [regex]::Match($remainingLine, "\*/")

                        if ($multilineEndMatch.Success) {
                            # Comment ends within this line
                            $line = $prefixBeforeComment + $remainingLine.Substring($multilineEndMatch.Index + 2)
                            # Reset j to continue checking for more comments
                            $j = $prefixBeforeComment.Length - 1
                            break
                        }
                        else {
                            # Comment spans multiple lines, continue reading
                            $i++
                            if ($i -lt $lines.Count) {
                                $remainingLine += "`n" + $lines[$i]
                            }
                        }
                    }

                    # If comment never closed, discard everything after `/*`
                    if (-not $multilineEndMatch.Success) {
                        $line = $prefixBeforeComment.TrimEnd()
                        break
                    }
                    continue
                }
            }
        }

        # Skip adding empty lines to result
        if ($line -match "^\s*$") { continue }

        $resultLines += $line.TrimEnd()
    }

    return $resultLines -join "`n"
}
#endregion

#region Configuration Management
function Get-ClimprConfig {
    [CmdletBinding()]
    param (
        # Specifies the deployment directory path as a mandatory parameter
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })] # Ensures the path exists and is a directory
        [string]$DeploymentDirectoryPath
    )

    # Stack to store paths of found climpr configuration files
    $configPaths = [System.Collections.Generic.Stack[string]]::new()
    
    # Traverse up the directory tree without changing the working directory
    $currentPath = Get-Item -Path $DeploymentDirectoryPath
    while ($currentPath -and ($currentPath.FullName -ne [System.IO.Path]::GetPathRoot($currentPath.FullName))) {
        foreach ($file in @("climprconfig.jsonc", "climprconfig.json")) {
            $filePath = Join-Path -Path $currentPath.FullName -ChildPath $file
            if (Test-Path $filePath) {
                $configPaths.Push($filePath)
                break # Skip .json file if .jsonc file is found
            }
        }
        $currentPath = $currentPath.Parent
    }

    # Merge configuration files
    $mergedConfig = @{}
    foreach ($path in $configPaths) {
        try {
            $config = Get-Content -Path $path -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $mergedConfig = Join-HashTable -Hashtable1 $mergedConfig -Hashtable2 $config
        }
        catch {
            Write-Warning "Skipping invalid JSON file: $path"
        }
    }

    return $mergedConfig
}

function Get-DeploymentConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ $_ | Test-Path -PathType Container })]
        [string]
        $DeploymentDirectoryPath,
        
        [Parameter(Mandatory)]
        [string]
        $DeploymentFileName,
        
        [ValidateScript({ $_ | Test-Path -PathType Leaf })]
        [string]
        $DefaultDeploymentConfigPath
    )

    #* Defaults
    $jsonDepth = 3

    #* Parse default deploymentconfig file
    $defaultDeploymentConfig = @{}

    if ($DefaultDeploymentConfigPath) {
        if (Test-Path -Path $DefaultDeploymentConfigPath) {
            $defaultDeploymentConfig = Get-Content -Path $DefaultDeploymentConfigPath | ConvertFrom-Json -Depth $jsonDepth -AsHashtable -NoEnumerate
            Write-Debug "[Get-DeploymentConfig()] Found default deploymentconfig file: $DefaultDeploymentConfigPath"
            Write-Debug "[Get-DeploymentConfig()] Found default deploymentconfig: $($defaultDeploymentConfig | ConvertTo-Json -Depth $jsonDepth)"
        }
        else {
            Write-Debug "[Get-DeploymentConfig()] Did not find the specified default deploymentconfig file: $DefaultDeploymentConfigPath"
        }
    }
    else {
        Write-Debug "[Get-DeploymentConfig()] No default deploymentconfig file specified."
    }

    #* Parse ClimprConfig
    $climprConfig = Get-ClimprConfig -DeploymentDirectoryPath $DeploymentDirectoryPath
    $climprConfigOptions = @{}
    if ($climprConfig.bicepDeployment -and $climprConfig.bicepDeployment.location) {
        $climprConfigOptions.Add("location", $climprConfig.bicepDeployment.location)
    }
    if ($climprConfig.bicepDeployment -and $climprConfig.bicepDeployment.azureCliVersion) {
        $climprConfigOptions.Add("azureCliVersion", $climprConfig.bicepDeployment.azureCliVersion)
    }

    #* Parse most specific deploymentconfig file
    $fileNames = @(
        $DeploymentFileName -replace "\.(bicep|bicepparam)$", ".deploymentconfig.json"
        $DeploymentFileName -replace "\.(bicep|bicepparam)$", ".deploymentconfig.jsonc"
        "deploymentconfig.json"
        "deploymentconfig.jsonc"
    )

    $config = @{}
    $foundFiles = @()
    foreach ($fileName in $fileNames) {
        $filePath = Join-Path -Path $DeploymentDirectoryPath -ChildPath $fileName
        if (Test-Path $filePath) {
            $foundFiles += $filePath
        }
    }

    if ($foundFiles.Count -eq 1) {
        $config = Get-Content -Path $foundFiles[0] | ConvertFrom-Json -NoEnumerate -Depth $jsonDepth -AsHashtable
        Write-Debug "[Get-DeploymentConfig()] Found deploymentconfig file: $($foundFiles[0])"
        Write-Debug "[Get-DeploymentConfig()] Found deploymentconfig: $($config | ConvertTo-Json -Depth $jsonDepth)"
    }
    elseif ($foundFiles.Count -gt 1) {
        throw "[Get-DeploymentConfig()] Found multiple deploymentconfig files. Only one deploymentconfig file is supported. Found files: [$foundFiles]"
    }
    else {
        if ($DefaultDeploymentConfigPath) {
            Write-Debug "[Get-DeploymentConfig()] Did not find deploymentconfig file. Using default deploymentconfig file."
        }
        else {
            Write-Debug "[Get-DeploymentConfig()] Did not find deploymentconfig file. No deploymentconfig applied."
        }
    }
    
    #* Merge configurations
    $deploymentConfig = Join-HashTable -Hashtable1 $defaultDeploymentConfig -Hashtable2 $climprConfigOptions
    $deploymentConfig = Join-HashTable -Hashtable1 $deploymentConfig -Hashtable2 $config

    #* Return config object
    $deploymentConfig
}
#endregion

#region Reference Resolution
function Get-BicepFileReferences {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $ParentPath,

        [string]
        $BasePath = (Resolve-Path -Path ".").Path
    )

    $pathIsBicepReference = $Path -match "^(?:br|ts)[:\/].+?"
    if ($pathIsBicepReference) {
        Write-Debug "[Get-BicepFileReferences()] Found: $Path"
        return $Path
    }
    
    #* Resolve path local to the calling Bicep template
    $parentFullPath = (Resolve-Path -Path $ParentPath).Path
    Push-Location $parentFullPath
    $fullPath = (Resolve-Path -Path $Path).Path
    Pop-Location

    #* Build relative paths and show debug info
    Push-Location $BasePath
    $relativePath = Resolve-Path -Relative -Path $fullPath
    $relativeParentPath = Resolve-Path -Relative -Path $parentFullPath
    Write-Debug "[Get-BicepFileReferences()] Started. Path: $relativePath. ParentPath: $relativeParentPath"
    Write-Debug "[Get-BicepFileReferences()] Found: $relativePath"
    Pop-Location

    #* Build regex pattern
    #* Pieces of the regex for better readability
    $rxOptionalSpace = "(?:\s*)"
    $rxSingleQuote = "(?:')"
    $rxUsing = "(?:using(?:\s+))"
    $rxExtends = "(?:extends(?:\s+))"
    $rxModule = "(?:module(?:\s+)(?:.+?)(?:\s+))"
    $rxFunctions = "(?:(?:loadFileAsBase64|loadJsonContent|loadYamlContent|loadTextContent)$rxOptionalSpace\()"

    #* Complete regex
    $regex = "(?:$rxUsing|$rxExtends|$rxModule|$rxFunctions)$rxSingleQuote(?:$rxOptionalSpace(.+?))$rxSingleQuote"

    #* Set temporary relative location
    Push-Location -Path $parentFullPath

    #* Find all matches and recursively call itself for each match
    if (Test-Path -Path $fullPath) {
        $item = Get-Item -Path $fullPath -Force
        
        $content = Get-Content -Path $fullPath -Raw
        $cleanContent = Remove-BicepComments -Content $content
        ($cleanContent | Select-String -AllMatches -Pattern $regex).Matches.Groups | 
        Where-Object { $_.Name -ne 0 } | 
        Select-Object -ExpandProperty Value | 
        Sort-Object -Unique | 
        ForEach-Object { Get-BicepFileReferences -ParentPath $item.Directory.FullName -Path $_ -BasePath $BasePath }
    }

    #* Revert to previous location
    Pop-Location

    #* Return path
    $relativePath
}

function Resolve-ParameterFileTarget {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]
        $Path,

        [Parameter(Mandatory, ParameterSetName = 'Content')]
        $Content
    )

    if ($Path) {
        $Content = Get-Content -Path $Path -Raw
    }
    $cleanContent = Remove-BicepComments -Content $Content

    #* Build regex pattern
    #* Pieces of the regex for better readability
    $rxMultiline = "(?sm)"
    $rxOptionalSpace = "(?:\s*)"
    $rxSingleQuote = "(?:')"
    $rxUsing = "(?:using)"
    $rxNone = "(none)"
    $rxReference = "(?:$($rxSingleQuote)(?:$($rxOptionalSpace)(.+?))$($rxSingleQuote))"

    #* Complete regex
    #* Normal bicepparam files
    # (?sm)^(?:\s*)(?:using)(?:\s*)(?:(?:')(?:(?:\s*)(.+?))(?:')).*?
    $regexReference = "$($rxMultiline)^$($rxOptionalSpace)$($rxUsing)$($rxOptionalSpace)$($rxReference).*?"

    #* Extendable bicepparam files
    # (?sm)^(?:\s*)(?:using)(?:\s*)(none).*?
    $regexNone = "$($rxMultiline)^$($rxOptionalSpace)$($rxUsing)$($rxOptionalSpace)$($rxNone).*?"

    if ($cleanContent -match $regexReference -or $cleanContent -match $regexNone) {
        $usingReference = $Matches[1]
        Write-Debug "[Resolve-ParameterFileTarget()] Valid 'using' statement found in parameter file content."
        Write-Debug "[Resolve-ParameterFileTarget()] Resolved: '$usingReference'"
    }
    else {
        throw "[Resolve-ParameterFileTarget()] Valid 'using' statement not found in parameter file content."
    }
    
    return $usingReference
}

function Resolve-TemplateDeploymentScope {
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [ValidateScript({ $_ | Test-Path -PathType Leaf })]
        [string]
        $DeploymentFilePath,

        [parameter(Mandatory)]
        [hashtable]
        $DeploymentConfig
    )

    $targetScope = ""
    $deploymentFile = Get-Item -Path $DeploymentFilePath
    
    if ($deploymentFile.Extension -eq ".bicep") {
        $referenceString = $deploymentFile.Name
    }
    elseif ($deploymentFile.Extension -eq ".bicepparam") {
        $referenceString = Resolve-ParameterFileTarget -Path $DeploymentFilePath
    }
    else {
        throw "Deployment file extension not supported. Only .bicep and .bicepparam is supported. Input deployment file extension: '$($deploymentFile.Extension)'"
    }

    if ($referenceString -match "^(br|ts)[\/:]") {
        #* Is remote template

        #* Resolve local cache path
        if ($referenceString -match "^(br|ts)\/(.+?):(.+?):(.+?)$") {
            #* Is alias

            #* Get active bicepconfig.json
            $bicepConfig = Get-BicepConfig -Path $DeploymentFilePath | Select-Object -ExpandProperty Config | ConvertFrom-Json -AsHashtable -NoEnumerate
            
            $type = $Matches[1]
            $alias = $Matches[2]
            $registryFqdn = $bicepConfig.moduleAliases[$type][$alias].registry
            $modulePath = $bicepConfig.moduleAliases[$type][$alias].modulePath
            $templateName = $Matches[3]
            $version = $Matches[4]
            $modulePathElements = $($modulePath -split "/"; $templateName -split "/")
        }
        elseif ($referenceString -match "^(br|ts):(.+?)/(.+?):(.+?)$") {
            #* Is FQDN
            $type = $Matches[1]
            $registryFqdn = $Matches[2]
            $modulePath = $Matches[3]
            $version = $Matches[4]
            $modulePathElements = $modulePath -split "/"
        }

        #* Find cached template reference
        $cachePath = "~/.bicep/$type/$registryFqdn/$($modulePathElements -join "$")/$version`$/"

        if (!(Test-Path -Path $cachePath)) {
            #* Restore .bicep or .bicepparam file to ensure templates are located in the cache
            bicep restore $DeploymentFilePath

            Write-Debug "[Resolve-TemplateDeploymentScope()] Target template is not cached locally. Running force restore operation on template."
            
            if (Test-Path -Path $cachePath) {
                Write-Debug "[Resolve-TemplateDeploymentScope()] Target template cached successfully."
            }
            else {
                Write-Debug "[Resolve-TemplateDeploymentScope()] Target template failed to restore. Target reference string: '$referenceString'. Local cache path: '$cachePath'"
                throw "Unable to restore target template '$referenceString'"
            }
        }

        #* Resolve deployment scope
        $armTemplate = Get-Content -Path "$cachePath/main.json" | ConvertFrom-Json -Depth 30 -AsHashtable -NoEnumerate
        
        switch -Regex ($armTemplate.'$schema') {
            "^.+?\/deploymentTemplate\.json#" {
                $targetScope = "resourceGroup"
            }
            "^.+?\/subscriptionDeploymentTemplate\.json#" {
                $targetScope = "subscription" 
            }
            "^.+?\/managementGroupDeploymentTemplate\.json#" {
                $targetScope = "managementGroup" 
            }
            "^.+?\/tenantDeploymentTemplate\.json#" {
                $targetScope = "tenant" 
            }
            default {
                throw "[Resolve-TemplateDeploymentScope()] Non-supported `$schema property in target template. Unable to ascertain the deployment scope." 
            }
        }
    }
    else {
        #* Is local template
        Push-Location -Path $deploymentFile.Directory.FullName
        
        #* Get template content
        $content = Get-Content -Path $referenceString -Raw
        Pop-Location
        
        #* Ensure Bicep is free of comments
        $cleanContent = Remove-BicepComments -Content $content
        
        #* Regex for finding 'targetScope' statement in template file
        if ($cleanContent -match "(?sm)^(?:\s)*?targetScope") {
            #* targetScope property is present
            
            #* Build regex pattern
            #* Pieces of the regex for better readability
            $rxMultiline = "(?sm)"
            $rxOptionalSpace = "(?:\s*)"
            $rxSingleQuote = "(?:')"
            $rxTarget = "(?:targetScope)"
            $rxScope = "(?:$rxSingleQuote(?:$rxOptionalSpace(resourceGroup|subscription|managementGroup|tenant))$rxSingleQuote)"

            #* Complete regex
            # (?sm)^(?:\s*)(?:targetScope)(?:\s*)=(?:\s*)(?:(?:')(?:(?:\s*)(resourceGroup|subscription|managementGroup|tenant))(?:')).*?
            $regex = "$($rxMultiline)^$($rxOptionalSpace)$($rxTarget)$($rxOptionalSpace)=$($rxOptionalSpace)$($rxScope).*?"

            if ($cleanContent -match $regex) {
                $targetScope = $Matches[1]
                Write-Debug "[Resolve-TemplateDeploymentScope()] Valid 'targetScope' statement found in template file content."
                Write-Debug "[Resolve-TemplateDeploymentScope()] Resolved: '$($targetScope)'"
            }
            else {
                throw "[Resolve-ParameterFileTarget()] Invalid 'targetScope' statement found in template file content. Must either not be present, or be one of 'resourceGroup', 'subscription', 'managementGroup' or 'tenant'"
            }
        }
        else {
            #* targetScope property is not present. Defaulting to 'resourceGroup'
            Write-Debug "[Resolve-TemplateDeploymentScope()] Valid 'targetScope' statement not found in parameter file content. Defaulting to resourceGroup scope"
            $targetScope = "resourceGroup"
        }
    }

    Write-Debug "[Resolve-TemplateDeploymentScope()] TargetScope resolved as: $targetScope"

    #* Validate required deploymentconfig properties for scopes
    switch ($targetScope) {
        "resourceGroup" {
            if (!$DeploymentConfig.ContainsKey("resourceGroupName")) {
                throw "[Resolve-TemplateDeploymentScope()] Target scope is resourceGroup, but resourceGroupName property is not present in the deploymentConfig file"
            }
        }
        "subscription" {}
        "managementGroup" {
            if (!$DeploymentConfig.ContainsKey("managementGroupId")) {
                throw "[Resolve-TemplateDeploymentScope()] Target scope is managementGroup, but managementGroupId property is not present in the deploymentConfig file"
            }
        }
        "tenant" {}
    }

    #* Return target scope
    $targetScope
}
#endregion

#region Core functions
function Get-BicepDeployments {
    [CmdletBinding()]
    param (
        [string[]]
        $DeploymentsRootDirectory,

        [ValidateSet(
            "All",
            "Modified"
        )]
        [string]
        $Mode,

        [string]
        $EventName, 

        [string]
        $Pattern, 

        [string]
        $EnvironmentPattern, 

        [string[]]
        $ChangedFiles = @(), 

        [switch]
        $Quiet
    )

    Write-Debug "Get-BicepDeployments.ps1: Started."
    Write-Debug "Input parameters: $($PSBoundParameters | ConvertTo-Json -Depth 3)"

    #* Establish defaults
    $scriptRoot = $PSScriptRoot
    Write-Debug "Working directory: '$((Resolve-Path -Path .).Path)'."
    Write-Debug "Script root directory: '$(Resolve-Path -Relative -Path $scriptRoot)'."

    #* Import Modules
    Import-Module $scriptRoot/DeployBicepHelpers.psm1 -Force

    #* Get deployments
    $validDirectories = foreach ($path in $DeploymentsRootDirectory) {
        if (Test-Path $path) {
            $path
        }
        else {
            Write-Debug "Path not found. $path. Skipping."
        }
    }

    $deploymentDirectories = @(Get-ChildItem -Directory -Path $validDirectories)
    Write-Debug "Found $($deploymentDirectories.Count) deployment directories."

    #* Build deployment map from deployment and environments
    $deploymentObjects = foreach ($deploymentDirectory in $deploymentDirectories) {
        $deploymentDirectoryRelativePath = Resolve-Path -Relative -Path $deploymentDirectory.FullName
        Write-Debug "[$($deploymentDirectory.Name)] Processing started."
        Write-Debug "[$($deploymentDirectory.Name)] Deployment directory path: '$deploymentDirectoryRelativePath'."
    
        #* Resolve deployment name
        $deploymentName = $deploymentDirectory.Name
    
        #* Exclude .examples deployment
        if ($deploymentName -in @(".example", ".examples")) {
            Write-Debug "[$deploymentName]. Skipped. Is example deployment."
            continue
        }

        #* Exclude common module directory names from deployment
        if ($deploymentName -in @("modules", ".bicep")) {
            Write-Debug "[$deploymentName]. Skipped. Is modules directory."
            continue
        }
    
        #* Resolve paths
        $templateFiles = @(Get-ChildItem -Path $deploymentDirectoryRelativePath -File -Filter "*.bicep")
        $parameterFiles = @(Get-ChildItem -Path $deploymentDirectoryRelativePath -File -Filter "*.bicepparam")
        $deploymentFiles = @()
 
        if ($parameterFiles.Count -gt 0) {
            #* Mode is .bicepparam
            Write-Debug "[$deploymentName]. Found $($parameterFiles.Count) .bicepparam files. Deployments determined by the .bicepparam files."
            $deploymentFiles = $parameterFiles
        }
        elseif ($templateFiles.Count -gt 0) {
            #* Mode is .bicep
            Write-Debug "[$deploymentName]. Found $($templateFiles.Count) .bicep files. Deployments determined by the .bicep files."
            $deploymentFiles = $templateFiles
        }
        else {
            #* Warn if no deployment file is found
            Write-Warning "[$deploymentName] Skipped. Invalid deployment. No .bicep or .bicepparam file found."
            Write-Debug "[$deploymentName] Skipped. Invalid deployment. No .bicep or .bicepparam file found."
        }
    
        #* Create deployment objects
        foreach ($deploymentFile in $deploymentFiles) {
            $deploymentFileRelativePath = Resolve-Path -Relative -Path $deploymentFile.FullName
            Write-Debug "[$deploymentName][$($deploymentFile.BaseName)] Processing deployment file: '$deploymentFileRelativePath'."
        
            #* Determine if it's an extended .bicepparam file
            Write-Debug "[$deploymentName][$($deploymentFile.BaseName)] Determining if the deployment is a .bicepparam file and the .bicepparam file is an extended parameter file."
            if ($deploymentFile.Extension -eq ".bicepparam") {
                $target = Resolve-ParameterFileTarget -Path $deploymentFileRelativePath
                if ($target -eq "none") {
                    Write-Debug "[$deploymentName][$($deploymentFile.BaseName)] Skipped file as it is an extended .bicepparam file."
                    continue
                }
                else {
                    Write-Debug "[$deploymentName][$($deploymentFile.BaseName)] Bicepparam file is not extended. Continuing. Target: '$target'."
                }
            }
            else {
                Write-Debug "[$deploymentName][$($deploymentFile.BaseName)] Deployment is a .bicep file. Continuing."
            }

            #* Resolve environment
            $environmentName = ($deploymentFile.BaseName -split "\.")[0]
            Write-Debug "[$deploymentName][$environmentName] Calculated environment: '$environmentName'."
        
            #* Get deploymentConfig
            $deploymentConfig = Get-DeploymentConfig `
                -DeploymentDirectoryPath $deploymentDirectoryRelativePath `
                -DeploymentFileName $deploymentFile.Name

            #* Get bicep references
            $references = Get-BicepFileReferences -ParentPath $deploymentDirectory.FullName -Path $deploymentFile.FullName
            $relativeReferences = foreach ($reference in $references) {
                #* Filter out br: and ts: references
                if (Test-Path -Path $reference) {
                    #* Resolve relative paths
                    Resolve-Path -Relative -Path $reference
                }
            }

            #* Create deploymentObject
            Write-Debug "[$deploymentName][$environmentName] Creating deploymentObject."
            $deploymentObject = [pscustomobject]@{
                Name           = "$deploymentName-$environmentName"
                Environment    = $environmentName
                DeploymentFile = $deploymentFile.FullName
                ParameterFile  = $deploymentFile.FullName #* [Deprecated] Kept for backward compatibility
                References     = $relativeReferences
                Deploy         = $true
                Modified       = $false
            }
        
            #* Resolve modified state
            if ($Mode -eq "Modified") {
                Write-Debug "[$deploymentName][$environmentName] Checking if any deployment references have been modified. Will only check local files."
                foreach ($changedFile in $changedFiles) {
                    if (!(Test-Path $changedFile)) {
                        continue
                    }
                    if ($deploymentObject.Modified) {
                        break
                    }
                    $deploymentObject.Modified = $deploymentObject.References -contains (Resolve-Path -Relative -Path $changedFile)
                }
            
                if ($deploymentObject.Modified) {
                    Write-Debug "[$deploymentName][$environmentName] At least one of the files used by the deployment have been modified. Deployment included."
                }
                else {
                    $deploymentObject.Deploy = $false
                    Write-Debug "[$deploymentName][$environmentName] No files used by the deployment have been modified. Deployment not included."
                }
            }
            else {
                Write-Debug "[$deploymentName][$environmentName] Skipping modified files check. GitHub event is `"$($EventName)`". All deployments included by default."
            }

            #* Pattern filter
            if ($deploymentObject.Deploy) {
                Write-Debug "[$deploymentName][$environmentName] Checking if deployment matches pattern filter."
                if ($Pattern) {
                    if ($deploymentObject.Name -match $Pattern) {
                        Write-Debug "[$deploymentName][$environmentName] Pattern [$Pattern] matched successfully. Deployment included."
                    }
                    else {
                        $deploymentObject.Deploy = $false
                        Write-Debug "[$deploymentName][$environmentName] Pattern [$Pattern] did not match. Deployment not included."
                    }
                }
                else {
                    Write-Debug "[$deploymentName][$environmentName] No pattern specified. Deployment included."
                }
            }
            else {
                Write-Debug "[$deploymentName][$environmentName] Skipping pattern check. Deployment already not included."
            }
        
            #* Exclude deployments that does not match the requested environment
            if ($deploymentObject.Deploy) {
                Write-Debug "[$deploymentName][$environmentName] Checking if environment matches desired environment."
                if ($EnvironmentPattern) {
                    if ($deploymentObject.Environment -match $EnvironmentPattern) {
                        Write-Debug "[$deploymentName][$environmentName] Desired environment pattern [$EnvironmentPattern] matches deployment environment [$($deploymentObject.Environment)]. Deployment included."
                    }
                    else {
                        $deploymentObject.Deploy = $false
                        Write-Debug "[$deploymentName][$environmentName] Desired environment pattern [$EnvironmentPattern] does not match deployment environment [$($deploymentObject.Environment)]. Deployment not included."
                    }
                }
                else {
                    Write-Debug "[$deploymentName][$environmentName] No desired environment pattern specified. Deployment is included."
                }
            }
            else {
                Write-Debug "[$deploymentName][$environmentName] Skipping environment check. Deployment already not included."
            }
        
            #* Exclude disabled deployments
            if ($deploymentObject.Deploy) {
                Write-Debug "[$deploymentName][$environmentName] Checking if deployment is disabled in the deploymentconfig file."
                if ($deploymentConfig.disabled) {
                    $deploymentObject.Deploy = $false
                    Write-Debug "[$deploymentName][$environmentName] Deployment is disabled for all triggers in the deploymentconfig file. Deployment is not included."
                }
                if ($deploymentConfig.triggers -and $deploymentConfig.triggers.ContainsKey($EventName) -and $deploymentConfig.triggers[$EventName].disabled) {
                    $deploymentObject.Deploy = $false
                    Write-Debug "[$deploymentName][$environmentName] Deployment is disabled for the current trigger [$EventName] in the deploymentconfig file. Deployment is not included."
                }
            }
            else {
                Write-Debug "[$deploymentName][$environmentName] Skipping deploymentconfig file deployment action check. Deployment already not included."
            }

            #* Return deploymentObject
            Write-Debug "[$deploymentName][$environmentName] deploymentObject: $($deploymentObject | ConvertTo-Json -Depth 1)"
            $deploymentObject
        }
    }

    #* Print deploymentObjects to console
    if (!$Quiet) {
        Write-Host "*** Deployments that are omitted ***"
        $omitted = @($deploymentObjects | Where-Object { !$_.Deploy })
        if ($omitted) {
            $i = 0
            $omitted | ForEach-Object {
                $i++
                $_ | Format-List * | Out-String | Write-Host 
                if ($i -lt $omitted.Count) { Write-Host "---" }
            }
        }
        else {
            Write-Host "None"
        }

        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host ""

        Write-Host "*** Deployments that are Included ***" -ForegroundColor Green
        $included = @($deploymentObjects | Where-Object { $_.Deploy })
        if ($included) {
            $i = 0
            $included | ForEach-Object {
                $i++
                $_ | Format-List * | Out-String | Write-Host -ForegroundColor Green 
                if ($i -lt $included.Count) { Write-Host "---" -ForegroundColor Green }
            }
        }
        else {
            Write-Host "None" -ForegroundColor Green
        }
    }

    #* Return deploymentObjects
    $result = @()
    foreach ($deploymentObject in ($deploymentObjects | Where-Object { $_.Deploy })) {
        $result += $deploymentObject
    }

    Write-Debug "Get-BicepDeployments.ps1: Completed"

    # Comma first to ensure array is not enumerated
    return , $result
}

function Resolve-DeploymentConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ $_ | Test-Path -PathType Leaf })]
        [string]
        $DeploymentFilePath,
    
        [Parameter(Mandatory)]
        [ValidateScript({ $_ | Test-Path -PathType Leaf })]
        [string]
        $DefaultDeploymentConfigPath,
    
        [Parameter(Mandatory)]
        [string]
        $GitHubEventName, 
    
        [Parameter(Mandatory = $false)]
        [bool]
        $DeploymentWhatIf = $false, 

        [switch]
        $Quiet
    )

    Write-Debug "Resolve-DeploymentConfig.ps1: Started"
    Write-Debug "Input parameters: $($PSBoundParameters | ConvertTo-Json -Depth 3)"

    #* Establish defaults
    $scriptRoot = $PSScriptRoot
    Write-Debug "Working directory: $((Resolve-Path -Path .).Path)"
    Write-Debug "Script root directory: $(Resolve-Path -Relative -Path $scriptRoot)"

    #* Resolve files
    $deploymentFile = Get-Item -Path $DeploymentFilePath
    $deploymentFileRelativePath = Resolve-Path -Relative -Path $deploymentFile.FullName
    $environmentName = ($deploymentFile.BaseName -split "\.")[0]
    $deploymentDirectory = $deploymentFile.Directory
    $deploymentRelativePath = Resolve-Path -Relative -Path $deploymentDirectory.FullName
    $deploymentFileName = $deploymentFile.Name

    #* Resolve deployment name and id
    $deploymentBaseName = $deploymentDirectory.Name
    $deploymentId = "$deploymentBaseName-$environmentName"

    Write-Debug "[$deploymentId] Deployment directory path: $deploymentRelativePath"
    Write-Debug "[$deploymentId] Deployment file path: $deploymentFileRelativePath"

    #* Create deployment objects
    Write-Debug "[$deploymentId] Processing deployment file: $deploymentFileRelativePath"

    #* Get deploymentConfig
    $param = @{
        DeploymentDirectoryPath     = $deploymentRelativePath
        DeploymentFileName          = $deploymentFileName
        DefaultDeploymentConfigPath = $DefaultDeploymentConfigPath
        Debug                       = ([bool]($PSBoundParameters.Debug))
    }
    $deploymentConfig = Get-DeploymentConfig @param

    #* Determine deployment file type
    if ($deploymentFile.Extension -eq ".bicepparam") {
        #* Is .bicepparam
        $templateReference = Resolve-ParameterFileTarget -Path $deploymentFileRelativePath
        $parameterFile = $deploymentFileRelativePath
    }
    elseif ($deploymentFile.Extension -eq ".bicep") {
        #* Is .bicep
        $templateReference = $deploymentFileRelativePath
        $parameterFile = $null
    }
    else {
        throw "Deployment file extension not supported. Only .bicep and .bicepparam is supported. Input deployment file extension: '$($deploymentFile.Extension)'"
    }

    #* Create deploymentObject
    Write-Debug "[$deploymentId] Creating deploymentObject"

    $deploymentObject = [pscustomobject]@{
        Deploy             = $true
        AzureCliVersion    = $deploymentConfig.azureCliVersion
        Environment        = $environmentName
        Type               = $deploymentConfig.type ?? "deployment"
        Scope              = Resolve-TemplateDeploymentScope -DeploymentFilePath $deploymentFileRelativePath -DeploymentConfig $deploymentConfig
        ParameterFile      = $parameterFile
        TemplateReference  = $templateReference
        DeploymentConfig   = $deploymentConfig
        DeploymentBaseName = $deploymentBaseName
        DeploymentId       = $deploymentId
        Name               = $deploymentConfig.name ?? "$deploymentId-$(git rev-parse --short HEAD)"
        Location           = $deploymentConfig.location
        ManagementGroupId  = $deploymentConfig.managementGroupId
        ResourceGroupName  = $deploymentConfig.resourceGroupName
    }

    #* Create deployment command
    $azCliCommand = @()
    switch ($deploymentObject.Type) {
        "deployment" {
            #* Create base command
            switch ($deploymentObject.Scope) {
                "resourceGroup" {
                    $azCliCommand += "az deployment group create"
                    $azCliCommand += "--resource-group $($deploymentObject.ResourceGroupName)"
                    $azCliCommand += "--name $($deploymentObject.Name)"
                }
                "subscription" { 
                    $azCliCommand += "az deployment sub create"
                    $azCliCommand += "--location $($deploymentObject.Location)"
                    $azCliCommand += "--name $($deploymentObject.Name)"
                }
                "managementGroup" {
                    $azCliCommand += "az deployment mg create"
                    $azCliCommand += "--location $($deploymentObject.Location)"
                    $azCliCommand += "--management-group-id $($deploymentObject.ManagementGroupId)"
                    $azCliCommand += "--name $($deploymentObject.Name)"
                }
                "tenant" {
                    $azCliCommand += "az deployment tenant create"
                    $azCliCommand += "--location $($deploymentObject.Location)"
                    $azCliCommand += "--name $($deploymentObject.Name)"
                }
                default {
                    Write-Output "::error::Unknown deployment scope."
                    throw "Unknown deployment scope."
                }
            }
        
            #* Add template reference parameter
            if ($deploymentObject.ParameterFile) {
                $azCliCommand += "--parameters $($deploymentObject.ParameterFile)"
            }
            else {
                $azCliCommand += "--template-file $($deploymentObject.TemplateReference)"
            }
    
            if ($DeploymentWhatIf) {
                $azCliCommand += "--what-if"
            }
        }

        "deploymentStack" {
            #* Throw an error if a the deployment is with scope 'tenant' and type 'deploymentStack' as this is not supported.
            if ($deploymentObject.Scope -eq 'tenant') {
                Write-Output "::error::Deployment stacks are not supported for tenant scoped deployments."
                throw "Deployment stacks are not supported for tenant scoped deployments."
            }

            #* Determine action for stack
            $stackAction = "create"
            if ($DeploymentWhatIf) {
                $stackAction = "validate"
            }

            #* Create base command
            switch ($deploymentObject.Scope) {
                "resourceGroup" {
                    $azCliCommand += "az stack group $stackAction"
                    $azCliCommand += "--resource-group $($deploymentObject.ResourceGroupName)"
                    $azCliCommand += "--name $($deploymentObject.Name)"
                }
                "subscription" { 
                    $azCliCommand += "az stack sub $stackAction"
                    $azCliCommand += "--location $($deploymentObject.Location)"
                    $azCliCommand += "--name $($deploymentObject.Name)"
                }
                "managementGroup" {
                    $azCliCommand += "az stack mg $stackAction"
                    $azCliCommand += "--location $($deploymentObject.Location)"
                    $azCliCommand += "--management-group-id $($deploymentObject.ManagementGroupId)"
                    $azCliCommand += "--name $($deploymentObject.Name)"
                }
                "tenant" {
                    $azCliCommand += "az stack tenant $stackAction"
                    $azCliCommand += "--location $($deploymentObject.Location)" 
                    $azCliCommand += "--name $($deploymentObject.Name)"
                }
                default {
                    Write-Output "::error::Unknown deployment scope."
                    throw "Unknown deployment scope."
                }
            }

            #* Add template reference parameter
            if ($deploymentObject.ParameterFile) {
                $azCliCommand += "--parameters $($deploymentObject.ParameterFile)"
            }
            else {
                $azCliCommand += "--template-file $($deploymentObject.TemplateReference)"
            }

            #* Add parameter: --yes
            if (!$DeploymentWhatIf) {
                $azCliCommand += "--yes"
            }

            #* Add parameter: --action-on-unmanage
            if ($null -ne $deploymentConfig.actionOnUnmanage) {
                if ($deploymentObject.Scope -eq "managementGroup") {
                    if ($deploymentConfig.actionOnUnmanage.resources -eq "delete" -and $deploymentConfig.actionOnUnmanage.resourceGroups -eq "delete" -and $deploymentConfig.actionOnUnmanage.managementGroups -eq "delete") {
                        $azCliCommand += "--action-on-unmanage deleteAll"
                    }
                    elseif ($deploymentConfig.actionOnUnmanage.resources -eq "delete") {
                        $azCliCommand += "--action-on-unmanage deleteResources"
                    }
                    else {
                        $azCliCommand += "--action-on-unmanage detachAll"
                    }
                }
                else {
                    if ($deploymentConfig.actionOnUnmanage.resources -eq "delete" -and $deploymentConfig.actionOnUnmanage.resourceGroups -eq "delete") {
                        $azCliCommand += "--action-on-unmanage deleteAll"
                    }
                    elseif ($deploymentConfig.actionOnUnmanage.resources -eq "delete") {
                        $azCliCommand += "--action-on-unmanage deleteResources"
                    }
                    else {
                        $azCliCommand += "--action-on-unmanage detachAll"
                    }
                }
            }
            else {
                $azCliCommand += "--action-on-unmanage detachAll"
            }

            #* Add parameter: --deny-settings-mode
            if ($null -ne $deploymentConfig.denySettings) {
                $azCliCommand += "--deny-settings-mode $($deploymentConfig.denySettings.mode)"

                #* Add parameter: --deny-settings-apply-to-child-scopes
                if ($deploymentConfig.denySettings.applyToChildScopes -eq $true) {
                    $azCliCommand += "--deny-settings-apply-to-child-scopes"
                }

                #* Add parameter: --deny-settings-excluded-actions
                if ($null -ne $deploymentConfig.denySettings.excludedActions) {
                    $azCliExcludedActions = ($deploymentConfig.denySettings.excludedActions | ForEach-Object { "`"$_`"" }) -join " " ?? '""'
                    if ($azCliExcludedActions.Length -eq 0) {
                        $azCliCommand += '--deny-settings-excluded-actions ""'
                    }
                    else {
                        $azCliCommand += "--deny-settings-excluded-actions $azCliExcludedActions"
                    }
                }

                #* Add parameter: --deny-settings-excluded-principals
                if ($null -ne $deploymentConfig.denySettings.excludedPrincipals) {
                    $azCliExcludedPrincipals = ($deploymentConfig.denySettings.excludedPrincipals | ForEach-Object { "`"$_`"" }) -join " " ?? '""'
                    if ($azCliExcludedPrincipals.Length -eq 0) {
                        $azCliCommand += '--deny-settings-excluded-principals ""'
                    }
                    else {
                        $azCliCommand += "--deny-settings-excluded-principals $azCliExcludedPrincipals"
                    }
                }
            }
            else {
                $azCliCommand += "--deny-settings-mode none"
            }

            #* Add parameter: --description
            if ([string]::IsNullOrEmpty($deploymentConfig.description)) {
                $azCliCommand += '--description ""'
            }
            else {
                $azCliCommand += "--description $($deploymentConfig.description)"
            }

            #* Add parameter: --deployment-resource-group
            if ($deploymentObject.Scope -eq "subscription" -and $deploymentConfig.deploymentResourceGroup) {
                $azCliCommand += "--deployment-resource-group $($deploymentConfig.deploymentResourceGroup)"
            }

            #* Add parameter: --deployment-subscription
            if ($deploymentObject.Scope -eq "managementGroup" -and $deploymentConfig.deploymentSubscription) {
                $azCliCommand += "--deployment-subscription $($deploymentConfig.deploymentSubscription)"
            }

            #* Add parameter: --bypass-stack-out-of-sync-error
            if ($deploymentConfig.bypassStackOutOfSyncError -eq $true) {
                $azCliCommand += "--bypass-stack-out-of-sync-error"
            }

            #* Add parameter: --tags
            if ($null -ne $deploymentConfig.tags -and $deploymentConfig.tags.Count -ge 1) {
                $azCliTags = ($deploymentConfig.tags.Keys | ForEach-Object { "'$_=$($deploymentConfig.tags[$_])'" }) -join " "
                $azCliCommand += "--tags $azCliTags"
            }
            else {
                $azCliCommand += '--tags ""'
            }
        }

        default {
            Write-Output "::error::Unknown deployment type."
            throw "Unknown deployment type."
        }
    }

    #* Add Azure Cli command to deploymentObject
    $deploymentObject | Add-Member -MemberType NoteProperty -Name "AzureCliCommand" -Value ($azCliCommand -join " ")

    #* Exclude disabled deployments
    Write-Debug "[$deploymentId] Checking if deployment is disabled in the deploymentconfig file."
    if ($deploymentConfig.disabled) {
        $deploymentObject.Deploy = $false
        Write-Debug "[$deploymentId] Deployment is disabled for all triggers in the deploymentconfig file. Deployment is skipped."
    }
    if ($deploymentConfig.triggers -and $deploymentConfig.triggers.ContainsKey($GitHubEventName) -and $deploymentConfig.triggers[$GitHubEventName].disabled) {
        $deploymentObject.Deploy = $false
        Write-Debug "[$deploymentId] Deployment is disabled for the current trigger [$GitHubEventName] in the deploymentconfig file. Deployment is skipped."
    }

    Write-Debug "[$deploymentId] deploymentObject: $($deploymentObject | ConvertTo-Json -Depth 3)"

    #* Print deploymentObject to console
    if (!$Quiet.IsPresent) {
        $deploymentObject | Format-List * | Out-String | Write-Host
    }

    Write-Debug "Resolve-DeploymentConfig.ps1: Completed"

    #* Return deploymentObject
    return $deploymentObject
}
#endregion
