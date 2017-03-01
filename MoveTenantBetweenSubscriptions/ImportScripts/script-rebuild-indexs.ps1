param([string]$server = "", [string]$database = "",[string]$user = "", [string]$pwd = "", [string]$tenant = "")

$connectionString = "Server=$server;uid=$user; pwd=$pwd;Database=$database;Integrated Security=False;"


$query = "
DECLARE @TableName varchar(255) 
DECLARE TableCursor CURSOR FOR
SELECT '[' + table_schema + '].[' + table_name + ']' FROM information_schema.tables
WHERE table_type = 'base table' AND table_schema = '$tenant'

OPEN TableCursor 
FETCH NEXT FROM TableCursor INTO @TableName 
WHILE @@FETCH_STATUS = 0 
BEGIN
exec('ALTER INDEX ALL ON ' + @TableName + ' REBUILD')
FETCH NEXT FROM TableCursor INTO @TableName 
END
CLOSE TableCursor 
DEALLOCATE TableCursor
";



$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString
$connection.Open()

#run script
$command = $connection.CreateCommand()
$command.CommandText  = $query
$command.CommandTimeout = 600
$command.ExecuteReader()

$connection.Close()




WRITE-HOST "Indexs rebuild!"