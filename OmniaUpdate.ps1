#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage

Param(
    [string] [Parameter(Mandatory=$true)] $WebsiteName, #http or https://*.azurewebsites.net
    [string] [Parameter(Mandatory=$true)] $SubscriptionName, #as in -subscriptionname param elsewhere
    [string] [Parameter(Mandatory=$true)] $ResourceGroupName, #as in -resourcegroupname param elsewhere
    [string] $Version,
    [switch] $force = $false,
    [switch] $whatIf = $false
)

$ErrorActionPreference = "Stop"
$OutputEncoding = New-Object -typename System.Text.UTF8Encoding
$thisScriptVersion = 1.0

function Get-ScriptDirectory
{
    #Obtains the executing directory of the script
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value;
    if($Invocation.PSScriptRoot)
    {
        $Invocation.PSScriptRoot;
    }
    Elseif($Invocation.MyCommand.Path)
    {
        Split-Path $Invocation.MyCommand.Path
    }
    else
    {
        $Invocation.InvocationName.Substring(0,$Invocation.InvocationName.LastIndexOf("\"));
    }
}

function BinariesUpdate
{
    #Performs the update of the binaries on the desired instance of the platform.
    param([string] $ResourceGroupName, [string] $Version, [string] $packageFolder, [bool] $whatIf = $false)
    
    $templateUri = "$packageFolder"+"updateTemplate.json"

    $templateParams = @{}

    $siteName = (($WebsiteName -split "://")[1] -split ".azurewebsites.net")[0]
    $templateParams.Add("siteName",$siteName);
    
    ## Test template validity
    $result = Test-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateUri $templateUri -TemplateParameterObject $templateParams
    if (-not ($result.Count -eq 0)){
        throw "Error validating deployment."
    }
    
    ## If ok, perform it
    Write-Host "Template is valid. Beginning update to version $Version on RG $ResourceGroupName"
    if (-not $whatIf){
        Write-Progress -id 1 -activity "Deploying template" -Status "In Progress"

        $deployment = New-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateUri $templateUri -TemplateParameterObject $templateParams
        Write-Host ("Deployment finished. Status: " + $deployment.ProvisioningState)
        Write-Progress -id 1 -activity "Deploying template" -Status "Completed" -Completed
    }
    else{
        Write-Host ("Dry run. Deployment not performed.")
    }
}

function GetCurrentVersion
{
    #Obtains the current platform version. For old versions, it's an API parse - in future, should be switched to a call to the service implemented in 1.200.166 : api/v1/Version/Get
    param([string] $WebsiteName)
    
    Write-Progress -id 2 -activity "Obtaining version" -Status "In Progress"
    $apiData = Invoke-WebRequest "$WebsiteName/api"
    $VersionStr = $apiData.ParsedHTML.body.getElementsByTagName("h1")[0].innerHTML
    Write-Progress -id 2 -activity "Obtaining version" -Status "Obtained" -Completed
    return $VersionStr.Split("-")[1].Split(" ")[1]
}

function GetMigrationsList
{
    #Obtains all of the migrations between the current and desired version, and verifies whether any of them are major changes (except for the desired version itself).
    #If any major changes exists, stops the process.
    param([string] $currentVersion, [System.Object[]] $versionList, [string] $Version )
    try{

        [array]$migrationList = $versionList | Select-Object @{name='Number';expression={(New-Object version $_."Number")}},PackageFolder,ExecuteScript,MajorChange | Where-Object Number -gt ([version] $currentVersion) |  Where-Object Number -le ([version] $Version) | Where-Object ExecuteScript -Eq "true" | Sort-Object -Property Number

        [array]$majorChanges = $versionList | Select-Object @{name='Number';expression={(New-Object version $_."Number")}},PackageFolder,ExecuteScript,MajorChange | Where-Object Number -gt ([version] $currentVersion) |  Where-Object Number -lt ([version] $Version) | Where-Object MajorChange -Eq "true"

        if ($majorChanges.Count -gt 0){
            throw "Major breaking changes detected that will not allow for a one-step platform migration. Please perform manual migrations for the versions: " + $majorChanges.Number
        }
        return $migrationList
    }
    catch{
        $PSCmdlet.WriteError($_)
        return
    }
}

function CreateTempFile
{
    #Creates a temporary file in a folder.
    param([string] $tempFolder, [string] $fileName, [string] $fileContents)
    
    $newFile = "$tempFolder"+"\"+"$fileName"
    Write-Host "Creating temporary file $newFile"
    [System.IO.File]::WriteAllText($newFile, $fileContents, [System.Text.Encoding]::UTF8)
    return $newFile
}

function PerformMigrations
{
    #Invokes any scripts that need to be invoked.
    param([System.Object[]] $migrationsList, [string] $migrationArgs, [bool] $whatIf)
    $siteName = (($WebsiteName -split "://")[1] -split ".azurewebsites.net")[0]

    if ($migrationList.Count -gt 0){
        Write-Host ("Detected "+$migrationList.Count+" migrations with scripts. Applying...")
        if (-not $whatIf){
            Write-Progress -id 3 -activity "Applying migrations" -Status "In Progress"
            ForEach ($obj In $migrationList){
                $scriptUri = $obj.PackageFolder+"migrationScript.ps1"
                $resp = (Invoke-WebRequest -Uri $scriptUri -Method GET -ContentType "application/octet-stream;charset=utf-8")
                $migrationScript = [system.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray());
                $tempPath = Get-ScriptDirectory #TODO: Investigate way to run scripts in memory without saving them
                $fileLocation = CreateTempFile $tempPath "migrationScript.ps1" $migrationScript
            
                Write-Host ("-------------------EXECUTING MIGRATION SCRIPT "+$obj.Number+" ---------------")
                Invoke-Expression "& `"$fileLocation`" $migrationArgs"
                Write-Host ("-------------------FINISHED EXECUTING MIGRATION SCRIPT "+$obj.Number+" ---------------")
            }
            #TODO: Delete file from $fileLocation

            Write-Progress -id 3 -activity "Applying migrations" -Status "Migrations Finished, Waiting on Site" -PercentComplete 50

            Start-Sleep -s 30 #To avoid race condition: see https://blogs.msdn.microsoft.com/hosamshobak/2016/05/26/arm-template-msdeploy-race-condition-issue/
            
            Write-Progress -id 3 -activity "Applying migrations" -Status "Completed" -completed
        }
        else{
            Write-Host ("Dry run. Migrations not performed.")
        }
    }
    else{
        Write-Host "No scripts necessary to execute. Just updating binaries."
    }
}

function BuildMigrationArgs
{
    #Creates an object that will be passed to all the scripts we execute, containing all the information we deem necessary.
    param([string] $ResourceGroupName,[string] $subscriptionName,[string] $WebsiteName )
    $migrationArgs = "-ResourceGroupName $ResourceGroupName -subscriptionName $subscriptionName -WebsiteName $WebsiteName"

    return $migrationArgs
}

function CompareVersions
{
    #Compares the version you want to update to and the version of the platform, and notifies the user if they are re-updating or rolling back an update. 
    #If it returns false, we should not execute migration scripts.
    param([version]$currentVersion, [version]$Version, [bool] $force)

    if ($currentVersion -eq $Version){
        Write-Host ("Current version is the same as the version you want to update to: $currentVersion")
        if (-not $force){
            $confirmation = Read-Host ("Are you sure you want to update again to ($currentVersion)? Y to continue")
            if ($confirmation -ne 'y' -and $confirmation -ne 'yes') {
                throw "Update process stopped due to user request."
            }
        }
        else{
            Write-Host ("-Force is set, proceeding with update")
        }
        return $false
    }
    elseif ($currentVersion -gt $Version){
        Write-Host ("Current version has a HIGHER VERSION NUMBER than the version you want to update to: ($currentVersion) > ($Version")
        if (-not $force){
            Read-Host ("Are you sure you want to update to ($currentVersion)? Y to continue")
            if ($confirmation -ne 'y' -and $confirmation -ne 'yes') {
                throw "Update process stopped due to user request."
            }
        }
        else{
            Write-Host ("-Force is set, proceeding with update")
        }
        return $false
    } 
    return $true
}

#Login-AzureRmAccount
Set-AzureRmContext -SubscriptionName $SubscriptionName

$updateFeed = [xml](Invoke-WebRequest "https://mymiswebdeploy.blob.core.windows.net/platformversions/updateFeed.xml").Content

## Version checks
$latestVersion = $updateFeed.PlatformVersions.Version[0]
Write-Host "Got update feed. Latest version:" $latestVersion.Number

$currentVersion = GetCurrentVersion $WebsiteName
Write-Host "Current version of $WebsiteName is $currentVersion"

$migrationArgs = BuildMigrationArgs $ResourceGroupName $subscriptionName $WebsiteName

if ($Version -eq ""){
    Write-Host "Going to update to the latest version."
    $versionInfo = $latestVersion
}
else{
    Write-Host "Searching for requested version $Version."
    $versionInfo = $updateFeed.PlatformVersions.Version | Where-Object "Number" -eq $Version
    if ($versionInfo){
        Write-Host "Desired version found."
    }
    else{
        throw "Requested platform version not found in update feed!"
    }
}

$canExecuteMigrations = CompareVersions ([version]$currentVersion) ([version]$versionInfo.Number) $force

Write-Host "Checking for migrations with scripts..."
$migrationList = @(GetMigrationsList $currentVersion $updateFeed.PlatformVersions.Version $versionInfo.Number)
if ($canExecuteMigrations){
    PerformMigrations $migrationList $migrationArgs $whatIf.IsPresent
}
BinariesUpdate $ResourceGroupName $versionInfo.Number $versionInfo.PackageFolder $whatIf.IsPresent