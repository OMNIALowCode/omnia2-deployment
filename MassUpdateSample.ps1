Param(
    [string] [Parameter(Mandatory=$true)] $SubscriptionName, #as in -subscriptionname param elsewhere
    [string] $updateScriptLocation = ".\OmniaUpdate.ps1"
)
Select-AzureRmSubscription -SubscriptionName  $SubscriptionName

$sitesList = New-Object System.Collections.Generic.List[System.Object]

 foreach ($group in $groups){ 
    $a = Get-AzureRmResource -ResourceType "Microsoft.Web/sites" -ResourceGroupName $group.ResourceGroupName;
    foreach ($site in $a){
        if ($site.Name -ne $snull -and $site.Name -notmatch "extensibility") { #do not want to update any Node websites!
            $sitesList.Add($site)
        }
    }
  }

foreach ($site in $sitesList){
    $params = "-ResourceGroupName `""+($site.ResourceGroupName)+"`" -WebsiteName `"https://"+$site.Name+".azurewebsites.net`" -SubscriptionName `"$SubscriptionName`" -Force "
    Write-Host ("Calling OmniaUpdate.ps1 with params: " + $params)
    Invoke-Expression "& `"$updateScriptLocation`" $params"
}