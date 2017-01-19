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

#remove if exists
$hash.Remove("Microsoft.WindowsAzure.Plugins.RemoteAccess.AccountEncryptedPassword")
$hash.Remove("Microsoft.WindowsAzure.Plugins.RemoteAccess.Enabled")
$hash.Remove("Microsoft.WindowsAzure.Plugins.RemoteForwarder.Enabled")
$hash.Remove("Microsoft.WindowsAzure.Plugins.Diagnostics.ConnectionString")
$hash.Remove("Microsoft.WindowsAzure.Plugins.RemoteAccess.AccountExpiration")
$hash.Remove("Microsoft.WindowsAzure.Plugins.RemoteAccess.AccountUsername")

Write-Host "New App Settings: " ($hash | Format-Table | Out-String)

Set-AzureRMWebAppSlot -ResourceGroupName $ResourceGroupName -Name $siteName -AppSettings $hash -Slot $Slot
