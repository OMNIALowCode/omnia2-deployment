param(
    [string] [Parameter(Mandatory=$true)] $tenant ,
    [string] [Parameter(Mandatory=$true)]$shortcode,
    [string] [Parameter(Mandatory=$true)] $tenantname,
    [string] $maxNumberOfUsers = "10",
    [string] $subGroupCode = "DefaultSubGroup",
    [string] [Parameter(Mandatory=$true)] $tenantAdmin,
    [string] [Parameter(Mandatory=$true)] $tenantAdminPwd,
    [string] [Parameter(Mandatory=$true)] $oem,
    [string] [Parameter(Mandatory=$true)] $master,
    [string] [Parameter(Mandatory=$true)] $masterpwd,
    [string] [Parameter(Mandatory=$true)] $WebsiteName, #http or https://*.azurewebsites.net
    [string] [Parameter(Mandatory=$true)] $SubscriptionName, #as in -subscriptionname param elsewhere
    [string] [Parameter(Mandatory=$true)] $ResourceGroupName #as in -resourcegroupname param elsewhere
)
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

$ErrorActionPreference = "Stop"

Set-AzureRmContext -SubscriptionName $SubscriptionName

$workingFolder = Get-ScriptDirectory

$siteName = (($WebsiteName -split "://")[1] -split ".azurewebsites.net")[0]
$webApp = Get-AzureRMWebAppSlot -ResourceGroupName $ResourceGroupName -Name $siteName -Slot "Production"

foreach ($setting in $webApp.SiteConfig.ConnectionStrings){
    if ($setting.Name -eq "MyMis.Storage.ConnectionString"){
        $storageAccountName = (($setting.ConnectionString -split ";AccountName=")[1] -split ";AccountKey=")[0]
        $storageAccessKey = ($setting.ConnectionString -split ";AccountKey=")[1]
    }
    elseif ($setting.Name -eq "MyMis.SQL.Core.ConnectionString"){
        $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -argumentlist ($setting.ConnectionString);
        $server = $builder.DataSource
        $database = $builder.InitialCatalog
        $user = $builder.UserID
        $pwd = $builder.Password
    }
}

foreach ($setting in $webApp.SiteConfig.AppSettings){
    if ($setting.Name -eq "MyMis.OAuth2.ClientID"){
        $apiID = $setting.Value
    }
    if ($setting.Name -eq "MyMis.ConnectorHub.Endpoint"){
        $apiEndpoint = $setting.Value
    }
}

#Preflight checks
if (-not $storageAccountName -or -not $storageAccessKey){
    throw "Invalid Storage configuration!"
}

if (-not $server -or -not  $database -or -not $user -or -not $pwd){
    throw "Invalid SQL Database configuration!"
}

if (-not $apiID -or -not $apiEndpoint){
    throw "Invalid API configuration!"
}
if (-not $oem -or -not $shortcode -or -not $tenantname -or -not $tenantAdmin -or -not $tenantAdminPwd -or -not $oem -or -not $master -or -not $masterpwd){
    throw "Invalid tenant creation configuration!"
}

#Begin Work
WRITE-HOST "$(Get-Date -format 'u') - Starting..."

Write-Progress -id 1 -activity "Importing Data" -Status "Creating Tenant"
cd .\ImportScripts
& .\script-tenant-create.ps1 -code $tenant -shortcode $shortcode -name $tenantname -maxNumberOfUsers $maxNumberOfUsers -subGroupCode $subGroupCode -tenantAdmin $tenantAdmin -tenantAdminPwd $tenantAdminPwd -oem $oem -apiID $apiID -apiEndpoint $apiEndpoint -master $master -masterpwd $masterpwd
cd ..

WRITE-HOST "$(Get-Date -format 'u') - Tenant created..."

try{
Write-Progress -id 1 -activity "Importing Data" -Status "Importing Database" -PercentComplete 12.5
cd .\ImportScripts
& .\script-import.ps1 -server $server -database $database -user $user -pwd $pwd -tenant $tenant
cd ..

WRITE-HOST "$(Get-Date -format 'u') - Data imported..."

Write-Progress -id 1 -activity "Importing Data" -Status "Importing Tables" -PercentComplete 25
cd .\ImportScripts
& .\script-table-import.ps1 -storageAccountName $storageAccountName -storageAccessKey $storageAccessKey -tenant $tenant
cd ..

WRITE-HOST "$(Get-Date -format 'u') - Tables imported..."

Write-Progress -id 1 -activity "Importing Data" -Status "Importing Blobs" -PercentComplete 37.5
cd .\ImportScripts
& .\script-blob-import.ps1 -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName -tenant $tenant -storageAccessKey $storageAccessKey
cd ..

WRITE-HOST "$(Get-Date -format 'u') - Blobs imported..."

Write-Progress -id 1 -activity "Importing Data" -Status "Importing Tenant Image" -PercentComplete 50
cd .\ImportScripts
& .\script-tenant-image-import.ps1 -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName -storageAccessKey $storageAccessKey 
cd ..

WRITE-HOST "$(Get-Date -format 'u') - Tenant Image imported..."

Write-Progress -id 1 -activity "Importing Data" -Status "Importing User Images" -PercentComplete 62.5
cd .\ImportScripts
& .\script-users-image-import.ps1 -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName -storageAccessKey $storageAccessKey 
cd ..

WRITE-HOST "$(Get-Date -format 'u') - Users Image imported..."

Write-Progress -id 1 -activity "Importing Data" -Status "Importing Users" -PercentComplete 75
cd .\ImportScripts
& .\script-users-import.ps1 -server $server -database $database -user $user -pwd $pwd -tenant $tenant -tenantAdmin $tenantAdminUser
cd ..

WRITE-HOST "$(Get-Date -format 'u') - Users imported..."

Write-Progress -id 1 -activity "Importing Data" -Status "Rebuilding DB Indexes for tenant" -PercentComplete 87.5
cd .\ImportScripts
& .\script-rebuild-indexs.ps1 -server $server -database $database -user $user -pwd $pwd -tenant $tenant
cd ..

Write-Progress -id 1 -activity "Importing Data" -Status "Completed" -Completed

WRITE-HOST "$(Get-Date -format 'u') - DB Indexs rebuilded..."

Write-Host "Data imported sucessfully. Please recreate the connectors."
}
catch{
    Write-Host ("Process failed! " + $_.Exception)
    $confirmation = Read-Host ("Do you want to delete the created tenant? Y to confirm")
    if ($confirmation -eq 'y' -or $confirmation -eq 'yes') {
        cd $workingFolder
        cd .\ImportScripts
        & .\script-tenant-delete.ps1 -code $tenant
        cd ..
    }
}