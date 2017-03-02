param([string]$code = "",[string]$apiID = "",[string]$apiEndpoint = "",[string]$master = "" ,[string]$masterpwd = "")

$thisfolder = $PSScriptRoot

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

$uri = $apiEndpoint + "v1/tenant/remove?tenantcode=$code"
$Authorization = "Bearer $accessToken"
try {
    $createResults = Invoke-WebRequest -Uri $uri -Method DELETE -Body $jsonRepresentation -ContentType "application/json" -Headers @{"Authorization" = "$Authorization"} 
}
catch {
    $createResults = $_.Exception;
    Write-Host $createResults;
}
$operationId = $createResults.Headers.'mymis-operation';
$commandId = $createResults.Headers.'mymis-command';

try{
    $uri = "https://$apiEndpoint"+"v1/00000000-0000-0000-0000-000000000000/operation/TrackingCommand?operation=$operationId&command=$commandId"
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
	Write-Host "Tenant $code deleted successfully"
}
catch{
    $tracking = $_.Exception;
    Write-Host $tracking;
}
cd $PSScriptRoot
