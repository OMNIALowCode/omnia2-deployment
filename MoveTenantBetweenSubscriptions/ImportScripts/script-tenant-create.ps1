param([string]$code = "",[string]$shortcode = "",[string]$name = "",[string]$maxNumberOfUsers = "",[string]$subGroupCode = "",[string]$tenantAdmin = "",[string]$tenantAdminPwd = "",[string]$oem = "",[string]$apiID = "",[string]$apiEndpoint = "",[string]$master = "" ,[string]$masterpwd = "")

$thisfolder = $PSScriptRoot


$jsonRepresentation = @"
{
  "Code": "$code",
  "ShortCode": "$shortcode",
  "Name": "$name",
  "MaxNumberOfUsers": "$maxNumberOfUsers",
  "SubGroupCode": "$subGroupCode",
  "Email": "$tenantAdmin",
  "AdminEmail": "$tenantAdmin",
  "TenantTemplate": "",
  "TenantType": "2",
  "Password": "$tenantAdminPwd",
  "TenantImage": null,
  "OEMBrand": "$oem",
  "Language": "en-US",
  "Parameters": ""
}
"@

function ObtainToken{
param([string] $apiUser, [string]$apiID, [string] $apiPassword, [string] $apiEndpoint)
    #GET Authentication
    $oAuthURL = $apiEndpoint + 'OAuth/Token'

    $grantString = "grant_type=password&client_id=$apiID&username=$apiUser&password=$apiPassword"

    $oauthdata = Invoke-RestMethod -Method Post -uri $oAuthURL -Body $grantString -ContentType "application/x-www-form-urlencoded"

    $accessToken = $oauthdata.access_token 
    $refreshToken = $oauthdata.refresh_token

    return $accessToken
}

$accessToken = ObtainToken $master $apiID $masterpwd $apiEndpoint

$uri = $apiEndpoint + "v1/tenant/create"

Write-host "Sending creation request for tenant $tenant to $uri"

$Authorization = "Bearer $accessToken"
try {
    $createResults = Invoke-WebRequest -Uri $uri -Method POST -Body $jsonRepresentation -ContentType "application/json" -Headers @{"Authorization" = "$Authorization"} 
}
catch {
    $createResults = $_.Exception;
    Write-Host $createResults;
}
$operationId = $createResults.Headers.'mymis-operation';
$commandId = $createResults.Headers.'mymis-command';

try{
    $uri = "$apiEndpoint"+"v1/00000000-0000-0000-0000-000000000000/operation/TrackingCommand?operation=$operationId&command=$commandId"
    $tracking = Invoke-WebRequest -Uri $Uri -Method GET -ContentType "application/json" -Headers @{"Authorization" = "$Authorization"} 
    $status = (ConvertFrom-Json $tracking.Content).CommandStatus
    while (($status = (ConvertFrom-Json $tracking.Content).CommandStatus) -ne "Completed"){
        if ($status -eq "Error"){
            $msg = "Error creating tenant:"+(ConvertFrom-Json $tracking.Content).CommandStatusMessage
            throw $msg
        }
        $msg = "Current status for operation "+ $operationId+ " : " +$status
        Write-Host $msg
        Start-Sleep -s 10
        $tracking = Invoke-WebRequest -Uri $Uri -Method GET -ContentType "application/json" -Headers @{"Authorization" = "$Authorization"} 
    }
	Write-Host "Tenant created successfully with code $desiredTenantCode"
}
catch{
    $tracking = $_.Exception;
    Write-Host $tracking;
    throw $_.Exception;
}
cd $PSScriptRoot
