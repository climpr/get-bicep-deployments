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
Import-Module $scriptRoot/support-functions.psm1 -Force

#* Get deployments
$validDirectories = foreach ($path in $DeploymentsRootDirectory) {
    if (Test-Path $path) {
        $path
    }
    else {
        Write-Debug "Path not found. $path. Skipping."
    }
}

$deployments = @(Get-ChildItem -Directory -Path $validDirectories)
Write-Debug "Found $($deployments.Count) deployments."

#* Build deployment map from deployment and environments
$deploymentObjects = foreach ($deployment in $deployments) {
    $deploymentRelativePath = Resolve-Path -Relative -Path $deployment.FullName
    Write-Debug "[$($deployment.Name)] Processing started."
    Write-Debug "[$($deployment.Name)] Deployment directory path: '$deploymentRelativePath'."
    
    #* Resolve deployment name
    $deploymentName = $deployment.Name
    
    #* Exclude .examples deployment
    if ($deploymentName -in @(".example", ".examples")) {
        Write-Debug "[$deploymentName]. Skipped. Is example deployment."
        continue
    }
    
    #* Resolve paths
    $parameterFiles = Get-ChildItem -Recurse -Depth 5 -Path $deploymentRelativePath -File -Filter "*.bicepparam"
    
    #* Warn if no parameter file is found
    if ($parameterFiles.Count -eq 0) {
        Write-Warning "[$deploymentName] Skipped. Invalid deployment. No .bicepparam file found."
        Write-Debug "[$deploymentName] Skipped. Invalid deployment. No .bicepparam file found."
    }
    
    #* Create deployment objects
    foreach ($parameterFile in $parameterFiles) {
        $parameterFileRelativePath = Resolve-Path -Relative -Path $parameterFile.FullName
        Write-Debug "[$deploymentName][$($parameterFile.BaseName)] Processing parameter file: '$parameterFileRelativePath'."
        
        #* Resolve environment
        $environmentName = ($parameterFile.BaseName -split "\.")[0]
        Write-Debug "[$deploymentName][$environmentName] Calculated environment: '$environmentName'."
        
        #* Get deploymentConfig
        $deploymentConfig = Get-DeploymentConfig `
            -DeploymentDirectoryPath $deploymentRelativePath `
            -ParameterFileName $parameterFileRelativePath

        #* Get bicep references
        $references = Get-BicepFileReferences -ParentPath $parameterFile.Directory.FullName -Path $parameterFile.FullName
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
            Name          = "$deploymentName-$environmentName"
            Environment   = $environmentName
            ParameterFile = $parameterFile.FullName
            References    = $relativeReferences
            Deploy        = $true
            Modified      = $false
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
$deploymentObjects | Where-Object { $_.Deploy }

Write-Debug "Get-BicepDeployments.ps1: Completed"