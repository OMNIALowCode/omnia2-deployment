param([string]$storageAccountName = "",[string]$storageAccessKey = "", [string]$tenant = "")


$tenantFormatted = $tenant.Replace('-','').ToLower()
$tableCommand = "https://$storageAccountName.table.core.windows.net/t$($tenantFormatted)Command/"
$tableOperation = "https://$storageAccountName.table.core.windows.net/t$($tenantFormatted)Operation/"

$accessKey = $storageAccessKey

$thisfolder = $PSScriptRoot

$folder = (Get-Item $thisfolder).Parent.FullName + "\Exported\tablefiles"

If (Test-Path $folder){
    REMOVE-ITEM $folder\* -Force -Recurse
}
Else{
    New-Item -ItemType Directory -Force $folder
}

WRITE-HOST $tableCommand
WRITE-HOST $tableOperation

  cd ${Env:ProgramFiles(x86)}
  cd "Microsoft SDKs\Azure\AzCopy"
  
  .\AzCopy.exe /Source:$tableCommand /Dest:"$folder\Command" /SourceKey:$accessKey /Manifest:table.manifest
  .\AzCopy.exe /Source:$tableOperation /Dest:"$folder\Operation" /SourceKey:$accessKey /Manifest:table.manifest

  cd $PSScriptRoot



WRITE-HOST "Table export completed"