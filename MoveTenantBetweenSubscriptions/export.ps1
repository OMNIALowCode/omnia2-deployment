param(
    [string]$tenant = "", 
    [string] [Parameter(Mandatory=$true)] $WebsiteName, #http or https://*.azurewebsites.net
    [string] [Parameter(Mandatory=$true)] $SubscriptionName, #as in -subscriptionname param elsewhere
    [string] [Parameter(Mandatory=$true)] $ResourceGroupName #as in -resourcegroupname param elsewhere
    )

$ErrorActionPreference = "Stop"

Set-AzureRmContext -SubscriptionName $SubscriptionName

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

#Preflight checks
if ($storageAccountName -eq $null -or $storageAccessKey -eq $null){
    throw "Invalid Storage configuration!"
}

if ($server -eq $null -or $database -eq $null -or $user -eq $null -or $pwd -eq $null){
    throw "Invalid SQL Database configuration!"
}

#Export process
WRITE-HOST "$(Get-Date -format 'u') - Starting export process..."

Write-Progress -id 1 -activity "Exporting Data" -Status "Exporting Blobs"
cd .\ExportScripts
& .\script-blob-export.ps1 -storageAccountName $storageAccountName -storageAccessKey $storageAccessKey -tenant $tenant
cd ..

WRITE-HOST "$(Get-Date -format 'u') - Blobs exported..."

Write-Progress -id 1 -activity "Exporting Data" -Status "Exporting Tables" -PercentComplete 16.66
cd .\ExportScripts
& .\script-table-export.ps1 -storageAccountName $storageAccountName -storageAccessKey $storageAccessKey -tenant $tenant
cd ..

WRITE-HOST "$(Get-Date -format 'u') - Tables exported..."

Write-Progress -id 1 -activity "Exporting Data" -Status "Exporting Tenant Image" -PercentComplete 33.33
cd .\ExportScripts
& .\script-tenant-image-export.ps1 -storageAccountName $storageAccountName -storageAccessKey $storageAccessKey -tenant $tenant
cd ..

WRITE-HOST "$(Get-Date -format 'u') - Tenant image exported..."

Write-Progress -id 1 -activity "Exporting Data" -Status "Exporting User Images" -PercentComplete 50
cd .\ExportScripts
& .\script-users-image-export.ps1 -storageAccountName $storageAccountName -storageAccessKey $storageAccessKey -server $server -database $database -user $user -pwd $pwd -tenant $tenant
cd ..

WRITE-HOST "$(Get-Date -format 'u') - users image exported..."

Write-Progress -id 1 -activity "Exporting Data" -Status "Exporting Users" -PercentComplete 66.66
cd .\ExportScripts
& .\script-users-export.ps1 -server $server -database $database -user $user -pwd $pwd -tenant $tenant
cd ..

WRITE-HOST "$(Get-Date -format 'u') - users exported..."

Write-Progress -id 1 -activity "Exporting Data" -Status "Exporting Database" -PercentComplete 83.33
cd .\ExportScripts
& .\script-export.ps1 -server $server -database $database -user $user -pwd $pwd -tenant $tenant
cd ..

Write-Progress -id 1 -activity "Exporting Data" -Status "Completed" -Completed

WRITE-HOST "$(Get-Date -format 'u') - data exported..."

Write-Host "Data exported sucessfully. Please execute import.ps1 to import the data to the destination subscription. Make sure you read the README before importing!"