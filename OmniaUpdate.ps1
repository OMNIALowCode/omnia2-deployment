#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage

Param(
    [string] [Parameter(Mandatory=$true)] $WebsiteName, #http or https://*.azurewebsites.net
    [string] [Parameter(Mandatory=$true)] $SubscriptionName, #as in -subscriptionname param elsewhere
    [string] [Parameter(Mandatory=$true)] $ResourceGroupName, #as in -resourcegroupname param elsewhere
    [string] $ResourceNameString,
    [string] $Version,
    [string] $Slot = "Production",
    [switch] $force = $false,
    [switch] $whatIf = $false,
	[string] $FeedURL = "https://mymiswebdeploy.blob.core.windows.net/platformversions/updateFeed.xml"
)

$ErrorActionPreference = "Stop"
$OutputEncoding = New-Object -typename System.Text.UTF8Encoding
$thisScriptVersion = 1.5

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
    param([string] $ResourceGroupName, [string] $Version, [string] $packageFolder, [bool] $whatIf = $false, [string] $Slot)
    
    $templateUri = "$packageFolder"+"updateTemplate.json"

    $templateParams = @{}

    $siteName = (($WebsiteName -split "://")[1] -split ".azurewebsites.net")[0]
    $templateParams.Add("siteName",$siteName);
    $templateParams.Add("slotName", $Slot);
    
    ## Test template validity
    $result = Test-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateUri $templateUri -TemplateParameterObject $templateParams
    if (-not ($result.Count -eq 0)){
        throw "Error validating deployment."
    }
    
    ## If ok, perform it
    Write-Host "Template is valid. Beginning update to version $Version on RG $ResourceGroupName, Website $siteName [$Slot]"
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
    try{ #Version is at least 1.200.166
        $VersionStr = Invoke-RestMethod "$WebsiteName/api/v1/Version/Get" -UseBasicParsing
        if (-not $VersionStr -or $VersionStr.Length -eq 0){
            throw "API error - version not found"
        }
    }
    catch{
        $apiData = Invoke-WebRequest "$WebsiteName/api" -UseBasicParsing
        $startPos = ($apiData.Content.IndexOf("Platform - ")+("Platform - ").Length)
        $versionLen = $apiData.Content.IndexOf("</h1>") - $startPos
        $VersionStr = $apiData.Content.Substring($startPos,$versionLen)
    }
    Write-Progress -id 2 -activity "Obtaining version" -Status "Obtained" -Completed
    return $VersionStr
}

function GetMigrationsList
{
    #Obtains all of the migrations between the current and desired version, and verifies whether any of them are major changes (except for the desired version itself).
    #If any major changes exists, stops the process.
    param([string] $currentVersion, [System.Object[]] $versionList, [string] $Version )
    try{

        [array]$migrationList = $versionList | Select-Object @{name='Number';expression={(New-Object version $_."Number")}},PackageFolder,ExecuteScript,MajorChange | Where-Object Number -gt ([version] $currentVersion) |  Where-Object Number -le ([version] $Version) | Where-Object ExecuteScript -Eq "true" | Sort-Object -Property Number

        [array]$majorChanges = $versionList | Select-Object @{name='Number';expression={(New-Object version $_."Number")}},PackageFolder,ExecuteScript,MajorChange | Where-Object Number -gt ([version] $currentVersion) |  Where-Object Number -lt ([version] $Version) | Where-Object MajorChange -Eq "true"

        if ($majorChanges -and $majorChanges.Count -gt 0){
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
    param([System.Object[]] $migrationList, [string] $migrationArgs, [bool] $whatIf, [string] $Slot)
    $siteName = (($WebsiteName -split "://")[1] -split ".azurewebsites.net")[0]
    
    if ($migrationList -and $migrationList.Count -gt 0){
        Write-Host ("Detected "+$migrationList.Count+" migrations with scripts. Applying...")
        if (-not $whatIf){
            Write-Progress -id 3 -activity "Applying migrations" -Status "In Progress"
            ForEach ($obj In $migrationList){
                $scriptUri = $obj.PackageFolder+"migrationScript.ps1"
                $resp = (Invoke-WebRequest -Uri $scriptUri -Method GET -ContentType "application/octet-stream;charset=utf-8" -UseBasicParsing)
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
    param([string] $ResourceGroupName,[string] $subscriptionName,[string] $WebsiteName,[string] $Slot, [string] $ResourceNameString )
    $migrationArgs = "-ResourceGroupName `"$ResourceGroupName`" -subscriptionName `"$subscriptionName`" -WebsiteName `"$WebsiteName`" -Slot `"$Slot`" -ResourceNameString `"$ResourceNameString`""

    return $migrationArgs
}

function CompareVersions
{
    #Compares the version you want to update to and the version of the platform, and notifies the user if they are re-updating or rolling back an update. 
    #If it returns false, we should not execute migration scripts.
    param([version]$currentVersion, [version]$Version, [bool] $force)

    if ($currentVersion -eq $Version){
        Write-Host ("Current version is the same as the version you want to update to: $currentVersion") -ForegroundColor Yellow
        if (-not $force){
            $confirmation = Read-Host ("Do you want to stop the update process? N to continue")
            if ($confirmation -ne 'n' -and $confirmation -ne 'no') {
                Write-Host "Update process stopped due to user request."
                Exit 0
            }
        }
        else{
            Write-Host ("-Force is set, stopping update") -ForegroundColor Yellow -BackgroundColor DarkMagenta
            Exit 0
        }
        return $false
    }
    elseif ($currentVersion -gt $Version){
        Write-Host ("Current version has a HIGHER VERSION NUMBER than the version you want to update to: ($currentVersion) -> ($Version)") -ForegroundColor Yellow
        if (-not $force){
            $confirmation = Read-Host ("Do you want to stop the update process? N to continue")
            if ($confirmation -ne 'n' -and $confirmation -ne 'no') {
                Write-host "Update process stopped due to user request."
                Exit 0
            }
        }
        else{
            Write-Host ("-Force is set, stopping update") -ForegroundColor Yellow -BackgroundColor DarkMagenta
            Exit 0
        }
        return $false
    } 
    return $true
}
Write-Host "Omnia Platform update process - version $thisScriptVersion"

#Login-AzureRmAccount
Set-AzureRmContext -SubscriptionName $SubscriptionName

$siteName = (($WebsiteName -split "://")[1] -split ".azurewebsites.net")[0]
if (-not $ResourceNameString){
    $ResourceNameString = ($siteName -split "wsmymis")[1]
}

$updateFeed = [xml](Invoke-WebRequest $FeedURL -UseBasicParsing).Content

## Version checks
$latestVersion = ($updateFeed.PlatformVersions.Version | Sort-Object @{e={$_.Number -as [version]}} -Descending)[0]
Write-Host "Got update feed. Latest version:" $latestVersion.Number

$currentVersion = GetCurrentVersion $WebsiteName
Write-Host "Current version of $WebsiteName is $currentVersion"

if ($slot -ne "Production"){
    $slotSiteName = $siteName + "-" + $Slot + ".azurewebsites.net"
    $currentSlotVersion = GetCurrentVersion $slotSiteName
    Write-Host "Current version of $WebsiteName in the slot $Slot is $currentSlotVersion"
    if ($currentVersion -ne $currentSlotVersion){
        Write-Host "The current version in slot $slot is not the same as the version in production! This may cause issues with configuration migrations." -ForegroundColor Yellow
        if (-not $force.IsPresent){
            $confirmation = Read-Host ("Are you sure you want to upgrade the slot $slot even though it may cause configuration issues?")
            if ($confirmation -ne 'y' -and $confirmation -ne 'yes') {
                throw "Swap not performed. Please re-create the site in slot $slot as a copy of the production site first."
            }
        }
        else{
            Write-Host ("-Force is set, proceeding with swap") -ForegroundColor Yellow -BackgroundColor DarkMagenta
        }
    }
}

$migrationArgs = BuildMigrationArgs $ResourceGroupName $subscriptionName $WebsiteName $Slot $ResourceNameString

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
    PerformMigrations $migrationList $migrationArgs $whatIf.IsPresent $Slot
}
BinariesUpdate $ResourceGroupName $versionInfo.Number $versionInfo.PackageFolder $whatIf.IsPresent $Slot

if ($Slot -ne "Production"){
    if (-not $force.IsPresent){
        $confirmation = Read-Host ("Are you sure you want to perform a swap from slot $Slot to slot Production?")
        if ($confirmation -ne 'y' -and $confirmation -ne 'yes') {
            Write-Host "Swap not performed. Please perform it manually via the Azure Portal." -ForegroundColor Yellow -BackgroundColor DarkMagenta
            return
        }
    }
    else{
        Write-Host ("-Force is set, proceeding with swap") -ForegroundColor Yellow -BackgroundColor DarkMagenta
    }
    $siteName = (($WebsiteName -split "://")[1] -split ".azurewebsites.net")[0]

    Write-Host "Beginning the swap between slot $Slot and slot Production."
    
    Write-Progress -id 4 -activity "Performing Swap" -Status "Beginning Swap"
    
	if (-not $whatIf.IsPresent){
		Swap-AzureRmWebAppSlot -ResourceGroupName $ResourceGroupName -Name $siteName -SourceSlotName $Slot -DestinationSlotName production
    }
    Write-Progress -id 4 -activity "Performing Swap" -Status "Completed" -completed
}

if (-not $whatIf.IsPresent){
    $finalVersion = GetCurrentVersion $WebsiteName
    Write-Host "Current version of $WebsiteName after update is $finalVersion"

    if ($finalVersion -ne $versionInfo.Number){
        throw ("Update inconsistent! Version in site after update finishing, $finalVersion, not the same as the desired version, "+$versionInfo.Number)
    }
}