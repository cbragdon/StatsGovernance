CREATE PROCEDURE dbo.usp_DRE_StatsCheckDatabaseGate_v1
    @RunID uniqueidentifier,@DatabaseName sysname,@CanProcess bit OUTPUT,@GateReason varchar(80) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @CanProcess=0,@GateReason=NULL;
    DECLARE @Mode varchar(10),@ExpectedID int,@ExpectedCreated datetime2(7),
        @InitialStatus varchar(24),@Scope xml,@CheckUTC datetime2(7)=SYSUTCDATETIME(),
        @Error int=NULL,@Message nvarchar(4000)=NULL,@Status varchar(40);
    SELECT @Mode=r.Mode,@ExpectedID=d.DatabaseIDAtSelection,@ExpectedCreated=d.DatabaseCreateDateAtSelection,
        @InitialStatus=d.SelectionStatus
    FROM dbo.StatsGovernanceRuns r JOIN dbo.StatsGovernanceRunDatabases d ON d.RunID=r.RunID
    WHERE r.RunID=@RunID AND r.RunStatus='RUNNING' AND d.DatabaseName=@DatabaseName COLLATE Latin1_General_100_BIN2;
    IF @Mode IS NULL THROW 51061,'An active run/database selection is required for scope revalidation.',1;
    BEGIN TRY
        IF NOT EXISTS(SELECT 1 FROM sys.databases WHERE database_id=@ExpectedID
            AND name=@DatabaseName COLLATE Latin1_General_100_BIN2 AND CONVERT(datetime2(7),create_date)=@ExpectedCreated)
            THROW 51062,'Database identity changed since selection. Review database creation, rename, restore, and scope configuration.',1;
        EXEC dbo.usp_DRE_StatsScopeLookup_v1 @DatabaseName,@Scope OUTPUT;
        IF @InitialStatus='EXCLUDED' OR @Scope.value('(/Scope/IsExcluded/text())[1]','bit')=1
            SELECT @Status='EXCLUDED',@GateReason='DATABASE_EXCLUDED';
        ELSE IF @Mode='ENFORCE' AND ISNULL(@Scope.value('(/Scope/EnabledForEnforcement/text())[1]','bit'),0)<>1
            SELECT @Status='APPROVAL_REVOKED',@GateReason='DATABASE_NOT_APPROVED',
                   @Error=51040,@Message=N'Database approval was revoked; remaining work was skipped.';
        ELSE IF NOT EXISTS(SELECT 1 FROM sys.databases WHERE database_id=@ExpectedID AND database_id<>2
            AND name<>N'SSISDB' AND is_distributor=0 AND state=0
            AND source_database_id IS NULL AND HAS_DBACCESS(name)=1
            AND ISNULL(sys.fn_hadr_is_primary_replica(name),1)=1)
            SELECT @Status='DATABASE_UNAVAILABLE',@GateReason='DATABASE_UNAVAILABLE',
                   @Error=51063,@Message=N'Database is unavailable, unsupported, or no longer hosted on the local primary replica; remaining work was skipped.';
        ELSE SELECT @Status='ALLOWED',@GateReason='SCOPE_ALLOWED',@CanProcess=1;
    END TRY
    BEGIN CATCH
        SELECT @Error=ERROR_NUMBER(),@Message=ERROR_MESSAGE(),@Status='SCOPE_CHECK_FAILED',@GateReason='SCOPE_CHECK_FAILED';
    END CATCH;
    UPDATE dbo.StatsGovernanceRunDatabases
    SET LastScopeStatus=@Status,ScopeAtLastCheckXml=@Scope,LastScopeCheckAtUTC=@CheckUTC,
        CollectionStatus=CASE WHEN @CanProcess=0 AND CollectionStatus='PENDING'
            THEN CASE WHEN @GateReason='DATABASE_EXCLUDED' THEN 'SKIPPED_EXCLUDED' ELSE 'SKIPPED_SCOPE_BLOCKED' END ELSE CollectionStatus END,
        ErrorNumber=COALESCE(@Error,ErrorNumber),ErrorMessage=COALESCE(@Message,ErrorMessage)
    WHERE RunID=@RunID AND DatabaseName=@DatabaseName COLLATE Latin1_General_100_BIN2;
    IF @CanProcess=0
        UPDATE dbo.StatsGovernanceTelemetry
        SET ExecutionStatus=CASE WHEN @GateReason='DATABASE_EXCLUDED' THEN 'SKIPPED_DATABASE_EXCLUDED' ELSE 'SKIPPED_SCOPE_BLOCKED' END,
            ExecutionReason=@GateReason,ErrorNumber=@Error,ErrorMessage=@Message
        WHERE RunID=@RunID AND DatabaseName=@DatabaseName COLLATE Latin1_General_100_BIN2
            AND ExecutionStatus IN ('PENDING','BLOCKED_CAPABILITY');
END;
