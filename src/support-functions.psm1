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
