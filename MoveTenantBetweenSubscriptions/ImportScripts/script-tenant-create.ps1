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
  "TenantType": "1",
  "Password": "$tenantAdminPwd",
  "TenantImage": null,
  "OEMBrand": "$oem",
  "Language": "en-US",
  "Parameters": ""
}
"@


$jsonRepresentation |  Out-File "$thisfolder\CreateTenant\tenant.json"


Write-Host "$thisfolder\CreateTenant\tenant.json"


cd .\CreateTenant

.\CreateMyMisTenant.exe $apiID $apiEndpoint $master $masterpwd

cd $PSScriptRoot