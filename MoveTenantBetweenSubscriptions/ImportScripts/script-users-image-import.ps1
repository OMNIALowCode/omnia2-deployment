
param([string]$resourceGroupName = "", [string]$storageAccountName = "", [string] $storageAccessKey = "")


$containerName = "user"

# Find the local folder where this PowerShell script is stored.
$currentLocation = Get-location
$thisfolder = $PSScriptRoot

# Upload files
$localfolder = (Get-Item $thisfolder).Parent.FullName + "\userImage\image"
if (Test-Path $localfolder)
{
    $destfolder = "image"
    $blobContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    $files = Get-ChildItem $localFolder 
    foreach($file in $files)
    {
      $fileName = "$localFolder\$file"
      $blobName = "$destfolder/$file"
      write-host "copying $fileName to $blobName"
      Set-AzureStorageBlobContent -File $filename -Container $containerName -Blob $blobName -Context $blobContext -Force
    } 
    write-host "All files in $localFolder uploaded to $containerName!"
}

