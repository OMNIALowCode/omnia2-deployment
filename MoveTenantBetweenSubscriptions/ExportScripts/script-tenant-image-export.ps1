param([string]$storageAccountName = "",[string]$storageAccessKey = "", [string]$tenant = "")

$tenantName = $tenant.Replace('-','').ToLower()

$container = "https://$storageAccountName.blob.core.windows.net/tenant"
$accessKey = $storageAccessKey

$thisfolder = $PSScriptRoot

$folder = (Get-Item $thisfolder).Parent.FullName + "\Exported\tenantImage"

If (Test-Path $folder){
    REMOVE-ITEM $folder\* -Force -Recurse
}
Else{
    New-Item -ItemType Directory -Force $folder
}


WRITE-HOST $container

  cd ${Env:ProgramFiles(x86)}
  cd "Microsoft SDKs\Azure\AzCopy"
  
  .\AzCopy.exe /Source:$container /Dest:$folder /SourceKey:$accessKey /Pattern:"image/$tenantName.jpg"
  .\AzCopy.exe /Source:$container /Dest:$folder /SourceKey:$accessKey /Pattern:"image/$tenantName.png"

  cd $PSScriptRoot


WRITE-HOST "Blob export completed!"