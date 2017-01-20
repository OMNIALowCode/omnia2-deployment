#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage

Param(
    [string] $WebsiteName,
    [string] $SubscriptionName,
    [string] $ResourceGroupName,
	[string] $Slot,
	[string] $ResourceNameString
)

$siteName = (($WebsiteName -split "://")[1] -split ".azurewebsites.net")[0]
$webApp = Get-AzureRMWebAppSlot -ResourceGroupName $ResourceGroupName -Name $siteName -Slot $Slot
$appSettingList = $webApp.SiteConfig.AppSettings

$hash = [ordered]@{}
ForEach ($kvp in $appSettingList) {
    $hash[$kvp.Name] = $kvp.Value
}

$location = (Get-AzureRmResourceGroup -ResourceGroupName $ResourceGroupName).Location
$locations = @(@{"locationName"=$location; "failoverPriority"=0})
$iprangefilter = ""
$consistencyPolicy = @{"defaultConsistencyLevel"="BoundedStaleness"; "maxIntervalInSeconds"=5; "maxStalenessPrefix"=100}
$DocumentDBProperties = @{"databaseAccountOfferType"="Standard"; "locations"=$locations; "consistencyPolicy"=$consistencyPolicy; "ipRangeFilter"=$iprangefilter}
New-AzureRmResource -ResourceType "Microsoft.DocumentDb/databaseAccounts" -ApiVersion "2015-04-08" -ResourceGroupName $ResourceGroupName -Location $location -Name ("docdb"+$ResourceNameString) -PropertyObject $DocumentDBProperties
$key = (Invoke-AzureRmResourceAction -action "listKeys" -ResourceType "Microsoft.DocumentDb/databaseAccounts" -Name ("docdb"+$ResourceNameString) -ResourceGroupName $ResourceGroupName -force).primaryMasterKey

$hash["MyMis.DocumentDBAccount"] = $key

Write-Host "New App Settings: " ($hash | Format-Table | Out-String)

Set-AzureRMWebAppSlot -ResourceGroupName $ResourceGroupName -Name $siteName -AppSettings $hash -Slot $Slot
