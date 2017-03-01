param([string]$server = "", [string]$database = "",[string]$user = "", [string]$pwd = "", [string]$tenant = "")

$connectionString = "Server=$server;uid=$user; pwd=$pwd;Database=$database;Integrated Security=False;"


$thisfolder = $PSScriptRoot
$datFolder = (Get-Item $thisfolder).Parent.FullName + "\Exported\datfiles"

$preconditionsQuery = "
DELETE FROM [$tenant].[USERS]

ALTER INDEX IX_MisEntity_ExternalCode ON [$tenant].[MisEntities]
DISABLE;

ALTER INDEX IX_Interaction_NumberSerie ON [$tenant].[MisEntities_Interaction]
DISABLE;
";

$posconditionsQuery = "ALTER INDEX ALL ON [$tenant].[MisEntities]
REBUILD;

ALTER INDEX ALL ON [$tenant].[MisEntities_Interaction]
REBUILD;";


$query = "SELECT TABLE_NAME 'Table'
	FROM INFORMATION_SCHEMA.TABLES
	WHERE TABLE_SCHEMA =  '"+ $tenant +"' AND TABLE_TYPE = 'BASE TABLE'"


$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString
$connection.Open()

#run pre conditions
$command = $connection.CreateCommand()
$command.CommandText  = $preconditionsQuery
$command.CommandTimeout = 600
$command.ExecuteNonQuery()


$command = $connection.CreateCommand()
$command.CommandText  = $query

$result = $command.ExecuteReader()




$table = new-object "System.Data.DataTable"

$table.Load($result)


Write-Progress -id 2 -activity "Copying Database Tables" -Status "Beginning Import"
$i = 0;
foreach ($Row in $table.Rows)
{ 
  $i++;
  $percent = 100*($i)/($table.Rows.Count)
  Write-Progress -id 2 -activity "Copying Database Tables" -Status "Copying Table $($Row[0])" -PercentComplete $percent

	WRITE-HOST "Copy of $($Row[0])..."
  
	bcp "[$($database)].[$($tenant)].[$($Row[0])]" in $datFolder\$($Row[0]).dat -f  $datFolder\$($Row[0]).xml -S "$($server)" -U "$($user)" -P "$($pwd)" -N -E
	
	
	
}
  Write-Progress -id 2 -activity "Copying Database Tables" -Status "Completed" -Completed

$connection.Close()

#run pos conditions
$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString
$connection.Open()

$command = $connection.CreateCommand()
$command.CommandText  = $posconditionsQuery
$command.CommandTimeout = 600
$command.ExecuteNonQuery()

#Update Auth.Tenants
$tenantInfo = Import-Csv $datFolder/'tenantInfo.csv'

$tenantVersionCheck = $connection.CreateCommand()
$tenantVersionCheck.CommandText = "SELECT DatabaseVersion FROM Auth.Tenants WHERE Code='$tenant'";

$versionResults = $tenantVersionCheck.ExecuteReader()

$table = new-object "System.Data.DataTable"

$table.Load($versionResults)
if ($table.Rows.Count -eq 1){
    $destinationDbVersion = ($table.Rows[0] | Select-Object DatabaseVersion)
    if ($destinationDbVersion.DatabaseVersion -ne $tenantInfo.DatabaseVersion){
        Write-Host ("Tenant database version is not the same as the version in the export:"+ $destinationDbVersion.DatabaseVersion+ " -> " + $tenantInfo.DatabaseVersion) -ForegroundColor Yellow
        $confirmation = Read-Host ("Do you want to stop the process? N to continue")
        if ($confirmation -ne 'n' -and $confirmation -ne 'no') {
            throw "Migration process stopped due to user request."
        }
    }
}
else{
    throw "Error: tenant not found in Auth.Tenants"
}

$tenantInfoCommand = $connection.CreateCommand()
$tenantInfoCommand.CommandText = "UPDATE Auth.Tenants SET Version="+($tenantInfo.Version)+", CustomerName='"+$tenantInfo.CustomerName+"', CustomerContactName='"+$tenantInfo.CustomerContactName+ `
	"', VATNumber='"+$tenantInfo.VATNumber+"', CustomerAddress='"+$tenantInfo.CustomerAddress+"', CustomerCountry='"+$tenantInfo.CustomerCountry+"' WHERE Code='$tenant'"

$tenantInfoCommand.ExecuteNonQuery()

$connection.Close()




WRITE-HOST "Data import completed!"