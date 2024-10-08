function Get-DeploymentConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ $_ | Test-Path -PathType Container })]
        [string]
        $DeploymentDirectoryPath,
        
        [Parameter(Mandatory)]
        [string]
        $ParameterFileName,
        
        [ValidateScript({ $_ | Test-Path -PathType Leaf })]
        [string]
        $DefaultDeploymentConfigPath
    )

    #* Defaults
    $jsonDepth = 3

    #* Parse default deploymentconfig.json
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

    #* Parse most specific deploymentconfig.json file
    $fileNames = @(
        $ParameterFileName -replace "\.bicepparam$", ".deploymentconfig.json"
        "deploymentconfig.json"
    )

    $config = @{}
    $found = $false
    foreach ($fileName in $fileNames) {
        $filePath = Join-Path -Path $DeploymentDirectoryPath -ChildPath $fileName
        if (Test-Path $filePath) {
            $found = $true
            $config = Get-Content -Path $filePath | ConvertFrom-Json -NoEnumerate -Depth $jsonDepth -AsHashtable
            Write-Debug "[Get-DeploymentConfig()] Found deploymentconfig file: $filePath"
            Write-Debug "[Get-DeploymentConfig()] Found deploymentconfig: $($config | ConvertTo-Json -Depth $jsonDepth)"
            break
        }
    }

    if (!$found) {
        if ($DefaultDeploymentConfigPath) {
            Write-Debug "[Get-DeploymentConfig()] Did not find deploymentconfig file. Using default deploymentconfig file."
        }
        else {
            Write-Debug "[Get-DeploymentConfig()] Did not find deploymentconfig file. No deploymentconfig applied."
        }
    }
    
    $deploymentConfig = Join-HashTable -Hashtable1 $defaultDeploymentConfig -Hashtable2 $config

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
    $rxModule = "(?:module(?:\s+)(?:.+?)(?:\s+))"
    $rxFunctions = "(?:(?:loadFileAsBase64|loadJsonContent|loadYamlContent|loadTextContent)$rxOptionalSpace\()"

    #* Complete regex
    $regex = "(?:$rxUsing|$rxModule|$rxFunctions)$rxSingleQuote(?:$rxOptionalSpace(.+?))$rxSingleQuote"

    #* Set temporary relative location
    Push-Location -Path $parentFullPath

    #* Find all matches and recursively call itself for each match
    if (Test-Path -Path $fullPath) {
        $item = Get-Item -Path $fullPath -Force
        
        (Get-Content -Path $fullPath -Raw | Select-String -AllMatches -Pattern $regex).Matches.Groups | 
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
