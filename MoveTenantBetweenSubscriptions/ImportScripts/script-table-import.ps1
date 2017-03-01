param([string]$storageAccountName = "",[string]$storageAccessKey = "", [string]$tenant = "")


$tenantFormatted = $tenant.Replace('-','').ToLower()
$tableCommand = "https://$storageAccountName.table.core.windows.net/t$($tenantFormatted)Command/"
$tableOperation = "https://$storageAccountName.table.core.windows.net/t$($tenantFormatted)Operation/"

$accessKey = $storageAccessKey

$thisfolder = $PSScriptRoot

$folder = (Get-Item $thisfolder).Parent.FullName + "\Exported\tablefiles"

Get-ChildItem -path $folder\Command -filter *.json | ForEach-Object { 



  cd ${Env:ProgramFiles(x86)}
  cd "Microsoft SDKs\Azure\AzCopy"
  
  
  $_.BaseName
  
  .\AzCopy.exe /Source:"$folder\Command" /Dest:$tableCommand /DestKey:$accessKey /Manifest:"table.manifest" /EntityOperation:InsertOrReplace
  

  cd $PSScriptRoot

  }
  
  
  
  
Get-ChildItem -path $folder\Operation -filter *.json | ForEach-Object { 



  cd ${Env:ProgramFiles(x86)}
  cd "Microsoft SDKs\Azure\AzCopy"
  
  
  $_.BaseName
  
  .\AzCopy.exe /Source:"$folder\Operation" /Dest:$tableOperation /DestKey:$accessKey /Manifest:"table.manifest" /EntityOperation:InsertOrReplace
  

  cd $PSScriptRoot

  }  


WRITE-HOST "Table import completed"