SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Selection xml,@ExpectedSystemCount int;

SELECT @ExpectedSystemCount=COUNT(*)
FROM sys.databases
WHERE database_id IN (1,3,4)
  AND database_id<>DB_ID()
  AND state=0
  AND source_database_id IS NULL
  AND HAS_DBACCESS(name)=1
  AND ISNULL(sys.fn_hadr_is_primary_replica(name),1)=1;

EXEC dbo.usp_DRE_StatsDatabaseSelection_v1
    @Databases=N'SYSTEM_DATABASES',@SelectionXml=@Selection OUTPUT,@EmitResult=0;

IF @Selection.value('count(/DatabaseSelection/Database)','int')<>@ExpectedSystemCount
    THROW 51700,'SYSTEM_DATABASES did not resolve the expected master, model, and msdb databases.',1;
IF @Selection.exist('/DatabaseSelection/Database[DatabaseID=2 or DatabaseName="SSISDB" or IsLocalPrimary=0 or ReadyForCollection=0]')=1
    THROW 51701,'SYSTEM_DATABASES returned an excluded, secondary, or unready database.',1;

EXEC dbo.usp_DRE_StatsDatabaseSelection_v1
    @Databases=N'ALL',@SelectionXml=@Selection OUTPUT,@EmitResult=0;
IF @Selection.exist('/DatabaseSelection/Database[DatabaseID=2 or DatabaseName="SSISDB" or IsLocalPrimary=0]')=1
    THROW 51702,'ALL returned tempdb, SSISDB, or an Always On secondary.',1;
IF EXISTS
(
    SELECT 1 FROM sys.databases AS d
    WHERE d.is_distributor=1
      AND @Selection.exist('/DatabaseSelection/Database[DatabaseID=sql:column("d.database_id")]')=1
)
    THROW 51703,'ALL returned a replication distribution database.',1;

EXEC dbo.usp_DRE_StatsDatabaseSelection_v1
    @Databases=N'USER_DATABASES',@SelectionXml=@Selection OUTPUT,@EmitResult=0;
IF @Selection.exist('/DatabaseSelection/Database[DatabaseID<=4 or DatabaseName="SSISDB" or IsLocalPrimary=0]')=1
    THROW 51704,'USER_DATABASES returned a system, SSISDB, or Always On secondary database.',1;

BEGIN TRY
    EXEC dbo.usp_DRE_StatsDatabaseSelection_v1
        @Databases=N'tempdb',@SelectionXml=@Selection OUTPUT,@EmitResult=0;
    THROW 51705,'Explicit tempdb selection was not rejected.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51031 THROW;
END CATCH;

IF DB_ID(N'SSISDB') IS NOT NULL
BEGIN
    BEGIN TRY
        EXEC dbo.usp_DRE_StatsDatabaseSelection_v1
            @Databases=N'SSISDB',@SelectionXml=@Selection OUTPUT,@EmitResult=0;
        THROW 51706,'Explicit SSISDB selection was not rejected.',1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER()<>51031 THROW;
    END CATCH;
END;

DECLARE @DistributionDatabase sysname=
(
    SELECT TOP (1) name FROM sys.databases WHERE is_distributor=1 ORDER BY database_id
);
IF @DistributionDatabase IS NOT NULL
BEGIN
    BEGIN TRY
        EXEC dbo.usp_DRE_StatsDatabaseSelection_v1
            @Databases=@DistributionDatabase,@SelectionXml=@Selection OUTPUT,@EmitResult=0;
        THROW 51707,'Explicit replication distribution database selection was not rejected.',1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER()<>51031 THROW;
    END CATCH;
END;

DECLARE @SecondaryDatabase sysname=
(
    SELECT TOP (1) name
    FROM sys.databases
    WHERE state=0
      AND source_database_id IS NULL
      AND HAS_DBACCESS(name)=1
      AND sys.fn_hadr_is_primary_replica(name)=0
    ORDER BY database_id
);
IF @SecondaryDatabase IS NOT NULL
BEGIN
    EXEC dbo.usp_DRE_StatsDatabaseSelection_v1
        @Databases=@SecondaryDatabase,@SelectionXml=@Selection OUTPUT,@EmitResult=0;
    IF @Selection.exist('/DatabaseSelection/Database[DatabaseName=sql:variable("@SecondaryDatabase") and IsLocalPrimary=0 and SelectionStatus="BLOCKED_SECONDARY" and ReadyForCollection=0]')<>1
        THROW 51708,'Explicit Always On secondary selection was not blocked.',1;
END;

SELECT N'DATABASE_SELECTION_CONTRACT_PASS' AS Status,@ExpectedSystemCount AS SupportedSystemDatabaseCount;
