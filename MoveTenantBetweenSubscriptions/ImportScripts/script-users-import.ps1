param([string]$server = "", [string]$database = "",[string]$user = "", [string]$pwd = "", [string]$tenant = "", [string] $tenantAdminUser = "")

$connectionString = "Server=$server;uid=$user; pwd=$pwd;Database=$database;Integrated Security=False;"

$thisfolder = $PSScriptRoot

$folder = (Get-Item $thisfolder).Parent.FullName + "\Exported\"

$query = (Get-Content ($folder+"\UsersInsertStatements.sql")).replace('@@TENANT@@',$tenant)

$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString
$connection.Open()

#run pre conditions
$command = $connection.CreateCommand()
$command.CommandText  = $query
$command.CommandTimeout = 600
$command.ExecuteNonQuery()


### IMPORT DOMAIN

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
WHERE t.Code = '$tenant' AND us.IsConnector = 0 
"


$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString
$connection.Open()
$command = $connection.CreateCommand()
$command.CommandText  = $query

$result = $command.ExecuteReader()

$table = new-object "System.Data.DataTable"

$table.Load($result)

$commandDomain = $connection.CreateCommand()
$commandDomain.CommandText  = "-- ADD TEMP COLUMN
ALTER TABLE [$tenant].Users
ADD OldUserID int null"
$commandDomain.CommandTimeout = 600
$commandDomain.ExecuteNonQuery()

#CREATE TEMP TABLE

$commandDomain = $connection.CreateCommand()
$commandDomain.CommandText  = "CREATE TABLE [$tenant].[#TEMP_Users](
	[ID] [bigint] NOT NULL,
	[Email] [nvarchar](256) NOT NULL,
	[ContactEmail] [nvarchar](256) NULL,
	[OldUserID] [bigint] NULL)"
$commandDomain.CommandTimeout = 600
$commandDomain.ExecuteNonQuery()



$statements = "
DECLARE @pv binary(16)
BEGIN TRANSACTION
BEGIN TRY


-- DISABLE CONSTRAINTS
ALTER TABLE [$tenant].UserPrivileges NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].MisEntities NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].MisEntities_Resource NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].MisEntities_Agent NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].MisEntities_UserDefinedEntity NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].MisEntities_Interaction NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].UsersInDomainRoles NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].Scripts NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].ScriptFiles NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].ReverseEntries NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].ApprovalStageDecisions NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].TransactionalEntityApprovalTrails NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].ApprovalTrails NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].BinaryDataInboxes NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].PolicySets NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].Policies NOCHECK CONSTRAINT ALL
ALTER TABLE [$tenant].Users NOCHECK CONSTRAINT ALL;

DISABLE TRIGGER [$tenant].[trgMisEntities_Interaction_InsertUpdate] ON [$tenant].[MisEntities_Interaction];


-- UPDATE USER IDS
UPDATE [$tenant].Users
SET OldUserID = ID 

INSERT INTO [$tenant].[#TEMP_Users]
SELECT ID, EMAIL, ContactEMAIL, OldUserID FROM [$tenant].Users

";


$usersEmails = "";

$statements = $statements + "declare @rowCount int `n";
	
foreach ($Row in $table.Rows)
{ 
	
	
	$statements = $statements + "UPDATE [$tenant].[#TEMP_Users] SET ID = $($Row['UserID']) WHERE EMAIL = '$($Row['Email'])'";

    $statements = $statements +  "
        select @rowCount=count(*) FROM [$tenant].[#TEMP_Users] WHERE EMAIL = '$($Row['Email'])'
        if @rowCount=0
        begin"


  $statements =  $statements +  " 
      INSERT INTO [$tenant].[#TEMP_Users]
	    SELECT $($Row['UserID']), '$($Row['Email'])', '$($Row['ContactEmail'])', NULL

      ; `n"


  $statements =  $statements  +  " end `n"

	if($usersEmails -ne "")
    {
	    $usersEmails = $usersEmails + " , ";
    }

	$usersEmails =  $usersEmails + "'$($Row['Email'])'";

}

$statements =  $statements + "




-- UPDATE DATA - REMOVED #TEMP_Users MOvE DATA TO ADMIN

DELETE  p FROM [$tenant].[UserViewPrivileges] p
INNER JOIN [$tenant].[UserPrivileges] up on p.UserPrivilegeID = up.ID
INNER JOIN [$tenant].#TEMP_Users u on u.OldUserID = up.UserID
WHERE u.Email NOT IN ($($usersEmails))

DELETE  p FROM [$tenant].UserPrivilegeApprovalStages p
INNER JOIN [$tenant].[UserPrivileges] up on p.UserPrivilegeID = up.ID
INNER JOIN [$tenant].#TEMP_Users u on u.OldUserID = up.UserID
WHERE u.Email NOT IN ($($usersEmails))


DELETE p
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].UserPrivileges p on u.OldUserID = p.UserID
WHERE u.Email NOT IN ($($usersEmails))



UPDATE p
set ModifiedByID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].MisEntities p on u.OldUserID = p.ModifiedByID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set CreatedByID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].MisEntities p on u.OldUserID = p.CreatedByID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set ApproverID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].MisEntities_Resource p on u.OldUserID = p.ApproverID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set ApproverID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].MisEntities_Agent p on u.OldUserID = p.ApproverID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))



UPDATE p
set UserID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].MisEntities_Agent p on u.OldUserID = p.UserID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))



UPDATE p
set ApproverID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].MisEntities_UserDefinedEntity p on u.OldUserID = p.ApproverID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))



UPDATE p
set ApproverID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].MisEntities_Interaction p on u.OldUserID = p.ApproverID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))



DELETE p
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].UsersInDomainRoles p on u.OldUserID = p.UserID
WHERE u.Email NOT IN ($($usersEmails))



UPDATE p
set CreatedByID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].Scripts p on u.OldUserID = p.CreatedByID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set ModifiedByID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].Scripts p on u.OldUserID = p.ModifiedByID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set CreatedByID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].ScriptFiles p on u.OldUserID = p.CreatedByID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set ModifiedByID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].ScriptFiles p on u.OldUserID = p.ModifiedByID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set UserID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].ReverseEntries p on u.OldUserID = p.UserID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set UserID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].ApprovalStageDecisions p on u.OldUserID = p.UserID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set UserID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].TransactionalEntityApprovalTrails p on u.OldUserID = p.UserID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set UserID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].ApprovalTrails p on u.OldUserID = p.UserID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set ApproverID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].ApprovalTrails p on u.OldUserID = p.ApproverID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set UserID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].BinaryDataInboxes p on u.OldUserID = p.UserID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))



UPDATE p
set ModifiedByID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].PolicySets p on u.OldUserID = p.ModifiedByID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set CreatedByID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].PolicySets p on u.OldUserID = p.CreatedByID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set ModifiedByID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].Policies p on u.OldUserID = p.ModifiedByID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))


UPDATE p
set CreatedByID = adminuser.ID
FROM [$tenant].#TEMP_Users u
INNER JOIN [$tenant].Policies p on u.OldUserID = p.CreatedByID
INNER JOIN [$tenant].#TEMP_Users adminuser on adminuser.Email = '$tenantAdminUser'
WHERE u.Email NOT IN ($($usersEmails))



DELETE FROM [$tenant].[#TEMP_Users]
WHERE EMAIL NOT IN ($($usersEmails))


-- MOVE USERS

DELETE FROM [$tenant].[Users]

INSERT INTO [$tenant].[Users]
SELECT ID, EMAIL, ContactEMAIL,OldUserID  FROM [$tenant].[#TEMP_Users]



-- UPDATE DATA
UPDATE p
set UserID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].UserPrivileges p on u.OldUserID = p.UserID



UPDATE p
set ModifiedByID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].MisEntities p on u.OldUserID = p.ModifiedByID


UPDATE p
set CreatedByID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].MisEntities p on u.OldUserID = p.CreatedByID


UPDATE p
set ApproverID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].MisEntities_Resource p on u.OldUserID = p.ApproverID


UPDATE p
set ApproverID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].MisEntities_Agent p on u.OldUserID = p.ApproverID


UPDATE p
set UserID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].MisEntities_Agent p on u.OldUserID = p.UserID


UPDATE p
set ApproverID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].MisEntities_UserDefinedEntity p on u.OldUserID = p.ApproverID


UPDATE p
set ApproverID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].MisEntities_Interaction p on u.OldUserID = p.ApproverID




UPDATE p
set UserID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].UsersInDomainRoles p on u.OldUserID = p.UserID




UPDATE p
set CreatedByID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].Scripts p on u.OldUserID = p.CreatedByID



UPDATE p
set ModifiedByID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].Scripts p on u.OldUserID = p.ModifiedByID



UPDATE p
set CreatedByID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].ScriptFiles p on u.OldUserID = p.CreatedByID



UPDATE p
set ModifiedByID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].ScriptFiles p on u.OldUserID = p.ModifiedByID



UPDATE p
set UserID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].ReverseEntries p on u.OldUserID = p.UserID



UPDATE p
set UserID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].ApprovalStageDecisions p on u.OldUserID = p.UserID



UPDATE p
set UserID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].TransactionalEntityApprovalTrails p on u.OldUserID = p.UserID



UPDATE p
set UserID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].ApprovalTrails p on u.OldUserID = p.UserID



UPDATE p
set ApproverID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].ApprovalTrails p on u.OldUserID = p.ApproverID



UPDATE p
set UserID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].BinaryDataInboxes p on u.OldUserID = p.UserID




UPDATE p
set ModifiedByID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].PolicySets p on u.OldUserID = p.ModifiedByID



UPDATE p
set CreatedByID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].PolicySets p on u.OldUserID = p.CreatedByID



UPDATE p
set ModifiedByID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].Policies p on u.OldUserID = p.ModifiedByID



UPDATE p
set CreatedByID = u.ID
FROM [$tenant].Users u
INNER JOIN [$tenant].Policies p on u.OldUserID = p.CreatedByID




-- DISABLE CONSTRAINTS
ALTER TABLE [$tenant].UserPrivileges CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].MisEntities CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].MisEntities_Resource CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].MisEntities_Agent CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].MisEntities_UserDefinedEntity CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].MisEntities_Interaction CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].UsersInDomainRoles CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].Scripts CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].ScriptFiles CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].ReverseEntries CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].ApprovalStageDecisions CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].TransactionalEntityApprovalTrails CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].ApprovalTrails CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].BinaryDataInboxes CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].PolicySets CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].Policies CHECK CONSTRAINT ALL
ALTER TABLE [$tenant].Users CHECK CONSTRAINT ALL;

ENABLE TRIGGER [$tenant].[trgMisEntities_Interaction_InsertUpdate] ON [$tenant].[MisEntities_Interaction];

-- REMOVE TEMP COLUMN
ALTER TABLE [$tenant].Users
DROP COLUMN OldUserID


DROP TABLE [$tenant].[#TEMP_Users]


COMMIT TRANSACTION
END TRY
BEGIN CATCH
        ROLLBACK TRANSACTION
        DECLARE @ErrorMessage AS NVARCHAR (4000);
        DECLARE @ErrorSeverity AS INT;
        DECLARE @ErrorState AS INT;
        SELECT @ErrorMessage = ERROR_MESSAGE(),
               @ErrorSeverity = ERROR_SEVERITY(),
               @ErrorState = ERROR_STATE();
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
END CATCH

";


$statements > LOG_UsersImport.sql

$commandDomain = $connection.CreateCommand()
$commandDomain.CommandText  = $statements
$commandDomain.CommandTimeout = 600
$commandDomain.ExecuteNonQuery()

$connection.Close()


WRITE-HOST "Users import complete!"
