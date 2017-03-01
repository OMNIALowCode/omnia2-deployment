param([string]$resourceGroupName = "", [string]$storageAccountName = "", [string]$tenant = "", [string] $storageAccessKey = "")

function importFiles([string]$localFolder, [string]$destFolder, [string] $storageAccessKey){
    if (Test-Path $localFolder){
        $blobContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccessKey
        Get-ChildItem $localFolder  | %{
          $fileName = "$localFolder\$_"
          $blobName = "$destfolder/$_"
          write-host "copying $fileName to $blobName"
          Set-AzureStorageBlobContent -File $filename -Container $containerName -Blob $blobName -Context $blobContext -Force
        } 
        write-host "All files in $localFolder uploaded to $containerName!"
    }
    else{
        write-host "No files to upload for $localFolder"
    }
}

$containerName = $tenant.Replace('-','').ToLower()

# Find the local folder where this PowerShell script is stored.
$currentLocation = Get-location
$thisfolder = $PSScriptRoot

# Upload files
$folder = (Get-Item $thisfolder).Parent.FullName + "\Exported\blobfiles"
$localfolder = "$folder\scripts"
$destfolder = "Scripts"
importFiles $localFolder $destFolder $storageAccessKey


$localfolder = "$folder\Report-Container"
$destfolder = "Report-Container"
importFiles $localFolder $destFolder $storageAccessKey


$localfolder = "$folder\Commands"
$destfolder = "Commands"
importFiles $localFolder $destFolder $storageAccessKey


$localfolder = "$folder\Binary"
$destfolder = "Binary"
importFiles $localFolder $destFolder $storageAccessKey