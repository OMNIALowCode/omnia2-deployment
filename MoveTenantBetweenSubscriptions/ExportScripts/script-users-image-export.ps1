param([string]$storageAccountName = "",[string]$storageAccessKey = "", [string]$server = "", [string]$database = "",[string]$user = "", [string]$pwd = "", [string]$tenant = "")


$connectionString = "Server=$server;uid=$user; pwd=$pwd;Database=$database;Integrated Security=False;"

$thisfolder = $PSScriptRoot

$container = "https://$storageAccountName.blob.core.windows.net/user"
$accessKey = $storageAccessKey

$folder = (Get-Item $thisfolder).Parent.FullName + "\Exported\userImage"

If (Test-Path $folder){
    REMOVE-ITEM $folder\* -Force -Recurse
}
Else{
    New-Item -ItemType Directory -Force $folder
}

$query = "select US.[Email]
from Auth.UserProfile us
INNER JOIN Auth.TenantUsers tu on us.UserID = tu.UserID
INNER JOIN Auth.Tenants t on t.ID = tu.TenantID
WHERE t.Code = '$tenant' AND US.[Status] = 1"


$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString
$connection.Open()
$command = $connection.CreateCommand()
$command.CommandText  = $query

$result = $command.ExecuteReader()

$table = new-object "System.Data.DataTable"

$table.Load($result)


foreach ($Row in $table.Rows)
{ 
  WRITE-HOST "Copy of $($Row[0])..."

    cd ${Env:ProgramFiles(x86)}
    cd "Microsoft SDKs\Azure\AzCopy"
  
    $text = $($Row[0]).ToLower()
    $md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $utf8 = new-object -TypeName System.Text.UTF8Encoding
    $hash = [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($text)))

  .\AzCopy.exe /Source:$container /Dest:$folder /SourceKey:$accessKey /Pattern:"image/$hash.jpg"

  cd $PSScriptRoot
  
}







