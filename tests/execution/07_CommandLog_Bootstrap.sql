/* SQLCMD-mode fresh utility-database test. Run from any working directory.
   Edit the two SQLCMD variables below when the project path or test name differs. */
:ON ERROR EXIT
:setvar ProjectRoot "D:\Projects\StatsGovernance"
:setvar UtilityDatabase "StatsGovCommandLogBootstrapV132"

USE [master];
IF DB_ID(N'$(UtilityDatabase)') IS NOT NULL
    THROW 51800,'The CommandLog bootstrap test database already exists.',1;
CREATE DATABASE [$(UtilityDatabase)];
ALTER DATABASE [$(UtilityDatabase)] SET COMPATIBILITY_LEVEL = 110;
GO

USE [$(UtilityDatabase)];
IF OBJECT_ID(N'dbo.CommandLog') IS NOT NULL
    THROW 51801,'The fresh utility database unexpectedly contains dbo.CommandLog.',1;

:r $(ProjectRoot)\src\installer\Install_v1.3.2.sql
:r $(ProjectRoot)\tests\contract\00_CommandLog.sql
GO

CREATE TABLE #CommandLogBefore
(
    ObjectID int NOT NULL,
    CreateDate datetime NOT NULL
);
INSERT #CommandLogBefore(ObjectID,CreateDate)
SELECT object_id,create_date
FROM sys.tables
WHERE object_id=OBJECT_ID(N'dbo.CommandLog',N'U');

:r $(ProjectRoot)\src\installer\Install_v1.3.2.sql
:r $(ProjectRoot)\tests\contract\00_CommandLog.sql
GO
:r $(ProjectRoot)\tests\contract\01_Tables.sql
GO
:r $(ProjectRoot)\tests\contract\02_Modules.sql
GO
:r $(ProjectRoot)\tests\contract\03_Database_Selection.sql
GO

IF NOT EXISTS
(
    SELECT 1
    FROM #CommandLogBefore AS b
    JOIN sys.tables AS t ON t.object_id=b.ObjectID AND t.create_date=b.CreateDate
    WHERE t.object_id=OBJECT_ID(N'dbo.CommandLog',N'U')
)
    THROW 51802,'The idempotent installer replaced the existing dbo.CommandLog table.',1;

SELECT N'COMMANDLOG_BOOTSTRAP_AND_RERUN_PASS' AS Status,DB_NAME() AS UtilityDatabase;
GO

USE [master];
ALTER DATABASE [$(UtilityDatabase)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$(UtilityDatabase)];
SELECT N'COMMANDLOG_BOOTSTRAP_CLEANUP_PASS' AS Status;
