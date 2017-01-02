#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage

Param(
    [string] $WebsiteName,
    [string] $SubscriptionName,
    [string] $ResourceGroupName,
	[string] $Slot
)

$siteName = (($WebsiteName -split "://")[1] -split ".azurewebsites.net")[0]
$webApp = Get-AzureRMWebAppSlot -ResourceGroupName $ResourceGroupName -Name $siteName -Slot $Slot
$appSettingList = $webApp.SiteConfig.AppSettings

Write-Host "Old App Settings: " ($appSettingList | Format-Table | Out-String)

$hash = [ordered]@{}
ForEach ($kvp in $appSettingList) {
    $hash[$kvp.Name] = $kvp.Value
}

$hash["NewSetting"] = "Add a new setting"
$hash["UpdateSetting"] = "Update an existing setting"

#remove if exists
$hash.Remove("UnnecessarySetting")
$hash.Remove("UnnecessarySettingThatDoesntExist")

Write-Host "New App Settings: " ($hash | Format-Table | Out-String)

Set-AzureRMWebAppSlot -ResourceGroupName $ResourceGroupName -Name $siteName -AppSettings $hash -Slot $Slot
