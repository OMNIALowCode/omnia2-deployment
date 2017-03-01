param([string]$storageAccountName = "",[string]$storageAccessKey = "", [string]$tenant = "")

$containerName = $tenant.Replace('-','').ToLower()

$container = "https://$storageAccountName.blob.core.windows.net/$($containerName)"
$accessKey = $storageAccessKey

$thisfolder = $PSScriptRoot

$folder = (Get-Item $thisfolder).Parent.FullName + "\Exported\blobfiles"

If (Test-Path $folder){
    REMOVE-ITEM $folder\* -Force -Recurse
}
Else{
    New-Item -ItemType Directory -Force $folder
}


WRITE-HOST $container

  cd ${Env:ProgramFiles(x86)}
  cd "Microsoft SDKs\Azure\AzCopy"
  
  .\AzCopy.exe /Source:$container /Dest:$folder /SourceKey:$accessKey /S

  cd $PSScriptRoot


WRITE-HOST "Blob export completed!"