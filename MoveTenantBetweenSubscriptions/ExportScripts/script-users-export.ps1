param([string]$server = "", [string]$database = "",[string]$user = "", [string]$pwd = "", [string]$tenant = "")


$connectionString = "Server=$server;uid=$user; pwd=$pwd;Database=$database;Integrated Security=False;"

$thisfolder = $PSScriptRoot


$query = "
select US.[UserID]
      ,US.[Email]
      ,US.[ContactEmail]
      ,US.[Name]
      ,convert(varchar, US.[Status]) 'Status'
      ,convert(varchar, US.[PasswordChangeRequired]) 'PasswordChangeRequired'
      ,COALESCE(convert(varchar, US.[LanguageID]), '1') 'LanguageID'
      ,convert(varchar, US.[IsConnector]) 'IsConnector'
from Auth.UserProfile us
INNER JOIN Auth.TenantUsers tu on us.UserID = tu.UserID
INNER JOIN Auth.Tenants t on t.ID = tu.TenantID
WHERE t.Code = '$tenant' AND us.IsConnector = 0"


$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString
$connection.Open()
$command = $connection.CreateCommand()
$command.CommandText  = $query

$result = $command.ExecuteReader()

$table = new-object "System.Data.DataTable"

$table.Load($result)

$insertStatements = "declare @rowCount int `n"
#$insertStatements =   $insertStatements + "SET IDENTITY_INSERT [Auth].[UserProfile] ON `n";


foreach ($Row in $table.Rows)
{ 
  WRITE-HOST "Copy of $($Row[0])..."
  
  $insertStatements = $insertStatements +  "
    select @rowCount=count(*) FROM Auth.UserProfile WHERE EMAIL ='$($Row['Email'])' 
    if @rowCount=0
    begin"

  $insertStatements = $insertStatements +  " INSERT INTO Auth.UserProfile ([Email] ,[ContactEmail] ,[Name] ,[Status] ,[PasswordChangeRequired] ,[LanguageID] ,[IsConnector]) VALUES ('$($Row['Email'])','$($Row['ContactEmail'])','$($Row['Name'])',$($Row['Status']),$($Row['PasswordChangeRequired']),$($Row['LanguageID']),$($Row['IsConnector'])); `n"

  $insertStatements = $insertStatements +  " end `n"
  
}

#$insertStatements = $insertStatements + "SET IDENTITY_INSERT [Auth].[UserProfile] OFF `n";

# MEMBERSHIP

$insertStatements = $insertStatements +  "`n`n"

$query = "SELECT 
us.Email,
convert(varchar,me.CreateDate,121) 'CreateDate',
NULL 'ConfirmationToken',
convert(varchar, IsConfirmed) 'IsConfirmed',
NULL 'LastPasswordFailureDate',
convert(varchar, PasswordFailuresSinceLastSuccess,121) 'PasswordFailuresSinceLastSuccess',
me.[Password],
convert(varchar,PasswordChangedDate,121) 'PasswordChangedDate',
[PasswordSalt],
NULL 'PasswordVerificationToken',
NULL 'PasswordVerificationTokenExpirationDate'
FROM [Auth].[webpages_Membership] me
INNER JOIN Auth.UserProfile us on me.UserID = us.UserID
INNER JOIN Auth.TenantUsers tu on us.UserID = tu.UserID
INNER JOIN Auth.Tenants t on t.ID = tu.TenantID
WHERE t.Code = '$tenant' AND us.IsConnector = 0 ";



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

    $insertStatements = $insertStatements +  "
    select @rowCount=count(*) FROM Auth.webpages_Membership WHERE UserID =(SELECT USERID FROM AUTH.UserProfile where email = '$($Row['Email'])') 
    if @rowCount=0
    begin"

  
  
  $insertStatements = $insertStatements +  " 
  INSERT INTO [Auth].[webpages_Membership]
  ([UserID]
           ,[CreateDate]
           ,[ConfirmationToken]
           ,[IsConfirmed]
           ,[LastPasswordFailureDate]
           ,[PasswordFailuresSinceLastSuccess]
           ,[Password]
           ,[PasswordChangedDate]
           ,[PasswordSalt]
           ,[PasswordVerificationToken]
           ,[PasswordVerificationTokenExpirationDate])
    VALUES (
    (SELECT USERID FROM AUTH.UserProfile where email = '$($Row['Email'])')
           ,'$($Row['CreateDate'])'
           ,NULL
           ,$($Row['IsConfirmed'])
           ,NULL
           ,$($Row['PasswordFailuresSinceLastSuccess'])
           ,'$($Row['Password'])'
           ,'$($Row['PasswordChangedDate'])'
           ,'$($Row['PasswordSalt'])'
           ,NULL
           ,NULL
    )
  ; `n"


    $insertStatements = $insertStatements +  " end `n"
  
}




# MEMBERSHIP ROLES

$insertStatements = $insertStatements +  "`n`n"

$query = "SELECT up.Email,
	ur.RoleID 
FROM Auth.UserProfile up
INNER JOIN [Auth].[webpages_UsersInRoles] upm on up.UserID = upm.UserID
INNER JOIN [Auth].[webpages_Roles] ur on upm.RoleID = upm.RoleID
INNER JOIN Auth.TenantUsers tu on up.UserID = tu.UserID
INNER JOIN Auth.Tenants t on t.ID = tu.TenantID
WHERE t.Code = '$tenant' AND up.IsConnector = 0 AND ur.RoleID <> 4";



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
  
      $insertStatements = $insertStatements +  "
    select @rowCount=count(*) FROM Auth.webpages_UsersInRoles WHERE UserID =(SELECT USERID FROM AUTH.UserProfile where email = '$($Row['Email'])') AND ROLEID = $($Row['RoleID'])
    if @rowCount=0
    begin"


  $insertStatements = $insertStatements +  " 
  INSERT INTO [Auth].[webpages_UsersInRoles]
    VALUES (
    (SELECT USERID FROM AUTH.UserProfile where email = '$($Row['Email'])')
    ,$($Row['RoleID'])
    )
  ; `n"


  $insertStatements = $insertStatements +  " end `n"
  
}




# TENANT USERS

$insertStatements = $insertStatements +  "`n`n"

$query = "select US.[Email]
      ,T.Code 'TenantCode'
        ,convert(varchar, tu.[Status]) 'Status'
           ,tu.[LastActive]
from Auth.UserProfile us
INNER JOIN Auth.TenantUsers tu on us.UserID = tu.UserID
INNER JOIN Auth.Tenants t on t.ID = tu.TenantID
WHERE t.Code = '$tenant' AND us.IsConnector = 0 ";



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
  
          $insertStatements = $insertStatements +  "
    select @rowCount=count(*) FROM Auth.TenantUsers WHERE UserID =(SELECT USERID FROM AUTH.UserProfile where email = '$($Row['Email'])') AND TenantID = (SELECT ID FROM AUTH.Tenants where code = '@@TENANT@@')
    if @rowCount=0
    begin"



  $insertStatements = $insertStatements +  " 
  INSERT INTO Auth.TenantUsers
  ([TenantID]
           ,[UserID]
           ,[Status]
           ,[LastActive])
    VALUES (
    (SELECT ID FROM AUTH.Tenants where code = '@@TENANT@@')
    ,(SELECT USERID FROM AUTH.UserProfile where email = '$($Row['Email'])')
    ,$($Row['Status'])
    ,NULL
    )
  ; `n"
  




  $insertStatements = $insertStatements +  " end `n"


}





$folder = (Get-Item $thisfolder).Parent.FullName + "\Exported\"

If (Test-Path ($folder + "\UsersInsertStatements.sql")){
    REMOVE-ITEM ($folder + "\UsersInsertStatements.sql")
}
$insertStatements > ($folder + "\UsersInsertStatements.sql")



$connection.Close()

WRITE-HOST "User export completed!"