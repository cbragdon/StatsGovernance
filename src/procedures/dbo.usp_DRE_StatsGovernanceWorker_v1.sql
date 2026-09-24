CREATE PROCEDURE dbo.usp_DRE_StatsGovernanceWorker_v1
    @Databases nvarchar(max),
    @Mode varchar(10) = 'RECOMMEND',
    @MAXDOP int = 4,
    @MinRowCountFloor bigint = 1000000,
    @LowSampleThresholdBase decimal(9,4) = 2.0,
    @LargeTableThresholdBase bigint = 20000000,
    @DefaultSamplePercentBase decimal(9,4) = NULL,
    @MaxExecutionTimeMinutes int = 300,
    @IOThroughputTier varchar(8) = 'STANDARD',
    @LegacyCEMultiplier decimal(9,4) = 2.0,
    @TargetTablesXml xml = NULL,
    @StatisticsScope varchar(20) = 'ALL'
AS
BEGIN
    -- Engine v1.3.2. Internal implementation; call a public dispatcher.
    -- The dispatcher applies the validated literal LOCK_TIMEOUT in the SAME
    -- dynamic batch that calls this worker. All nested work inherits it.
    DECLARE @InvocationStartedUTC datetime2(7)=SYSUTCDATETIME();
    SET NOCOUNT ON;
    SET ANSI_WARNINGS ON;
    SET NUMERIC_ROUNDABORT OFF;
    SET ROWCOUNT 0;
    SET ARITHABORT ON;
    SET ANSI_PADDING ON;
    SET CONCAT_NULL_YIELDS_NULL ON;

    -- No unrequested impersonation, TRUSTWORTHY changes, or permission grants.
    IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1
        THROW 51020, 'v1 is an administrative procedure; execute as sysadmin or an authorized sysadmin-owned Agent job.', 1;
    IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2
        THROW 51021, 'Run outside an explicit transaction with IMPLICIT_TRANSACTIONS OFF.', 1;
    IF (CONVERT(int,SERVERPROPERTY('ProductMajorVersion')) NOT IN (13,14,15,16,17)
        AND CONVERT(int,SERVERPROPERTY('EngineEdition'))<>8)
        OR CONVERT(int,SERVERPROPERTY('EngineEdition')) NOT IN (2,3,4,8)
        THROW 51022, 'Unsupported engine/version for v1.', 1;
    IF (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID())<110
        THROW 51023, 'The utility database compatibility level must be 110 or higher.', 1;

    DECLARE @Capabilities xml;
    EXEC dbo.usp_DRE_StatsCapabilities_v1 @CapabilitiesXml=@Capabilities OUTPUT,@EmitResult=0;
    IF ISNULL(@Capabilities.value('(/Capabilities/SupportedEngine/text())[1]','bit'),0)<>1
        THROW 51046, 'Unrecognized engine/build. Capability rules did not authorize this target.',1;

    SET @Mode=UPPER(LTRIM(RTRIM(@Mode)));
    SET @IOThroughputTier=UPPER(LTRIM(RTRIM(@IOThroughputTier)));
    SET @Databases=LTRIM(RTRIM(@Databases));
    SET @StatisticsScope=UPPER(LTRIM(RTRIM(@StatisticsScope)));
    IF @Mode IS NULL OR @Mode NOT IN ('OBSERVE','RECOMMEND','ENFORCE')
        THROW 51024, 'Mode must be OBSERVE, RECOMMEND, or ENFORCE.', 1;
    IF @Databases IS NULL OR LEN(@Databases)=0
        THROW 51025, 'Specify one database, a comma-separated list, ALL, SYSTEM_DATABASES, or USER_DATABASES.', 1;
    IF @StatisticsScope IS NULL OR @StatisticsScope NOT IN ('ALL','INDEX_ONLY','AUTO_ONLY','USER_ONLY','NON_AUTO')
        THROW 51120, 'StatisticsScope must be ALL, INDEX_ONLY, AUTO_ONLY, USER_ONLY, or NON_AUTO.', 1;
    IF @MAXDOP IS NULL OR @MAXDOP NOT BETWEEN 1 AND 64
        THROW 51026, 'MAXDOP must be 1 through 64; zero/unbounded parallelism is not accepted by this engine.', 1;
    IF @MinRowCountFloor IS NULL OR @MinRowCountFloor<0
       OR @LargeTableThresholdBase IS NULL OR @LargeTableThresholdBase<@MinRowCountFloor
       OR @LargeTableThresholdBase<1
        THROW 51027, 'Invalid row-count floor or large-table threshold.', 1;
    IF @LowSampleThresholdBase IS NULL OR @LowSampleThresholdBase<0 OR @LowSampleThresholdBase>100
       OR (@DefaultSamplePercentBase IS NOT NULL AND (@DefaultSamplePercentBase<=0 OR @DefaultSamplePercentBase>100))
       OR @LegacyCEMultiplier IS NULL OR @LegacyCEMultiplier<1 OR @LegacyCEMultiplier>100
        THROW 51028, 'Invalid percentage or advisory CE multiplier.', 1;
    IF @MaxExecutionTimeMinutes IS NULL OR @MaxExecutionTimeMinutes NOT BETWEEN 0 AND 525600
        THROW 51029, 'MaxExecutionTimeMinutes must be 0 through 525600; zero means unlimited.', 1;
    IF @IOThroughputTier IS NULL OR @IOThroughputTier NOT IN ('LOW','STANDARD','HIGH')
        THROW 51030, 'IOThroughputTier must be LOW, STANDARD, or HIGH.', 1;

    DECLARE @SelectionXml xml;
    EXEC dbo.usp_DRE_StatsDatabaseSelection_v1
        @Databases=@Databases,@SelectionXml=@SelectionXml OUTPUT,@EmitResult=0;
    DECLARE @DbList TABLE
    (
        DatabaseID int NOT NULL PRIMARY KEY,DatabaseName sysname COLLATE DATABASE_DEFAULT NOT NULL,
        DatabaseCreateDateLocal datetime2(7) NOT NULL,IsExcluded bit NOT NULL,
        EnabledForEnforcement bit NOT NULL,ReadyForCollection bit NOT NULL,
        SelectionStatus varchar(24) COLLATE DATABASE_DEFAULT NOT NULL,SelectionReason varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,ScopeXml xml NOT NULL
    );
    INSERT @DbList
    SELECT n.d.value('(DatabaseID/text())[1]','int'),n.d.value('(DatabaseName/text())[1]','nvarchar(128)'),
        n.d.value('(DatabaseCreateDateLocal/text())[1]','datetime2(7)'),n.d.value('(IsExcluded/text())[1]','bit'),
        n.d.value('(EnabledForEnforcement/text())[1]','bit'),n.d.value('(ReadyForCollection/text())[1]','bit'),
        n.d.value('(SelectionStatus/text())[1]','varchar(24)'),n.d.value('(SelectionReason/text())[1]','varchar(80)'),
        n.d.query('Scope')
    FROM @SelectionXml.nodes('/DatabaseSelection/Database') n(d);

    -- Targeted table execution is deliberately restricted to one resolved database.
    -- This protects object-name resolution and prevents the same token from silently
    -- binding to different schemas/tables in different databases.
    DECLARE @TargetDatabaseName sysname=NULL,@TargetXmlDatabaseName sysname=NULL;
    IF @TargetTablesXml IS NOT NULL
    BEGIN
        IF @TargetTablesXml.exist('/TableTargets/Table[1]')<>1
            THROW 51121, 'TargetTablesXml was supplied but contains no canonical table targets.',1;
        IF (SELECT COUNT(*) FROM @DbList)<>1
            THROW 51122, 'Table targeting requires exactly one resolved database.',1;
        SELECT TOP(1) @TargetDatabaseName=DatabaseName FROM @DbList;
        SET @TargetXmlDatabaseName=CASE WHEN @TargetTablesXml.exist('/TableTargets/DatabaseName[1]')=1
             THEN @TargetTablesXml.value('(/TableTargets/DatabaseName/text())[1]','nvarchar(128)') END;
        IF @TargetXmlDatabaseName IS NULL
           OR @TargetXmlDatabaseName COLLATE Latin1_General_100_BIN2<>@TargetDatabaseName COLLATE Latin1_General_100_BIN2
            THROW 51123, 'Canonical target-table database identity does not match the resolved database.',1;
    END;
    -- Excluded databases do not participate in target availability/approval checks.
    IF EXISTS(SELECT 1 FROM @DbList WHERE IsExcluded=0 AND ReadyForCollection=0)
        THROW 51033, 'Non-excluded selections must be online, accessible, non-snapshot supported databases.', 1;
    DECLARE @SelectedDatabaseCount int=(SELECT COUNT(*) FROM @DbList WHERE IsExcluded=0),
            @InitialExcludedDatabaseCount int=(SELECT COUNT(*) FROM @DbList WHERE IsExcluded=1);

    IF @Mode='ENFORCE' AND @SelectedDatabaseCount>0
    BEGIN
        IF OBJECT_ID(N'dbo.CommandLog',N'U') IS NULL
            THROW 51034, 'Install the standard Ola Hallengren dbo.CommandLog table in the utility database before ENFORCE.', 1;
        -- Check standard column types without changing the table.
        IF EXISTS
        (
            SELECT 1 FROM (VALUES
                (N'ID',56,4),(N'DatabaseName',231,256),(N'SchemaName',231,256),
                (N'ObjectName',231,256),(N'ObjectType',175,2),(N'IndexName',231,256),
                (N'IndexType',48,1),(N'StatisticsName',231,256),(N'PartitionNumber',56,4),
                (N'ExtendedInfo',241,-1),(N'Command',231,-1),(N'CommandType',231,120),
                (N'StartTime',42,8),(N'EndTime',42,8),(N'ErrorNumber',56,4),(N'ErrorMessage',231,-1)
            ) expected(ColumnName,TypeID,LengthBytes)
            LEFT JOIN sys.columns c ON c.object_id=OBJECT_ID(N'dbo.CommandLog') AND c.name COLLATE DATABASE_DEFAULT = expected.ColumnName COLLATE DATABASE_DEFAULT
            WHERE c.column_id IS NULL OR c.system_type_id<>expected.TypeID OR c.max_length<>expected.LengthBytes
        ) OR COLUMNPROPERTY(OBJECT_ID(N'dbo.CommandLog'),N'ID','IsIdentity')<>1
            THROW 51035, 'CommandLog does not match the expected standard schema. Review it; do not alter it automatically.', 1;
        IF EXISTS(SELECT 1 FROM @DbList WHERE IsExcluded=0 AND EnabledForEnforcement<>1)
            THROW 51036, 'Every non-excluded database must be explicitly approved in StatsGovernanceScope before ENFORCE.', 1;
    END;

    DECLARE @RunID uniqueidentifier=NEWID(), @StartedUTC datetime2(7)=@InvocationStartedUTC,
            @DeadlineUTC datetime2(7),
            @LockTimeout int, @HaveAppLock bit=0, @LockResult int,
            @FailedCount int=0, @PostcheckFailures int=0, @BlockedCount int=0, @WindowExpired bit=0,
            @Db sysname, @StatsXml xml, @EnvXml xml, @Facts xml, @NewFacts xml,
            @Override xml, @Decision xml, @Policy xml, @Command nvarchar(max),
            @TelemetryID bigint, @LogID int, @ObjectID int, @StatsID int,
            @Schema sysname, @Table sysname, @Stat sysname, @Eligible bit,
            @Reason varchar(80), @Method varchar(16), @Sample decimal(19,6), @SampleRows bigint,
            @CanExecute bit,@CapabilityReason varchar(80),@PostStatus varchar(40),@AfterPersist decimal(19,6),
            @Persist bit, @NoRecompute bit, @IndexName sysname, @IndexType tinyint,
            @ObjectType char(2), @ExtendedInfo xml, @CmdStartedUTC datetime2(7),
            @CmdEndedUTC datetime2(7), @CmdError int, @CmdMessage nvarchar(4000),
            @TraceFlags xml, @LegacyFlag bit=0,@ModernFlag bit=0,@DynamicFlag bit=0,@Progress nvarchar(4000),
            @RunStatus varchar(32), @OverrideID int, @GateAllowed bit, @GateReason varchar(80);

    SET @DeadlineUTC=CASE WHEN @MaxExecutionTimeMinutes=0 THEN NULL
                          ELSE DATEADD(MINUTE,@MaxExecutionTimeMinutes,@StartedUTC) END;
    SELECT @LockTimeout=LockTimeoutMilliseconds,
           @Policy=(SELECT @MinRowCountFloor AS MinRowCountFloor,
                    s.UpdateThresholdPercent,s.MinModificationCount,s.MinUpdateIntervalMinutes,
                    @LowSampleThresholdBase AS LowSampleThresholdBase,
                    @LargeTableThresholdBase AS LargeTableThresholdBase,
                    @DefaultSamplePercentBase AS DefaultSamplePercentBase,
                    @LegacyCEMultiplier AS LegacyCEMultiplier,
                    s.SkewSamplingEnabled,s.ModerateSkewThresholdPercent,
                    s.HighSkewThresholdPercent,s.ExtremeSkewThresholdPercent,
                    s.HighSkewSampleRows,s.ExtremeSkewSampleRows,
                    @Mode AS Mode,@Databases AS Databases,@MAXDOP AS RequestedMAXDOP,
                    @MaxExecutionTimeMinutes AS MaxExecutionTimeMinutes,
                    @IOThroughputTier AS IOThroughputTier,@StatisticsScope AS StatisticsScope,
                    @TargetTablesXml AS TargetTablesXml,s.LockTimeoutMilliseconds,
                    @Capabilities.query('/Capabilities')
                    FOR XML PATH('Policy'),TYPE)
    FROM dbo.StatsGovernanceSettings s WHERE SettingsID=1 AND SchemaVersion='1.3.0';
    IF @Policy IS NULL THROW 51037, 'Missing or incompatible governance settings.', 1;

    CREATE TABLE #SGTraceFlags(TraceFlag int NULL,Status int NULL,[Global] int NULL,[Session] int NULL);
    INSERT #SGTraceFlags EXEC(N'DBCC TRACESTATUS (9481,2312,2371,-1) WITH NO_INFOMSGS;');
    SELECT @TraceFlags=(SELECT * FROM #SGTraceFlags FOR XML PATH('Flag'),ROOT('TraceFlags'),TYPE);
    IF EXISTS(SELECT 1 FROM #SGTraceFlags WHERE TraceFlag=9481 AND Status=1) SET @LegacyFlag=1;
    IF EXISTS(SELECT 1 FROM #SGTraceFlags WHERE TraceFlag=2312 AND Status=1) SET @ModernFlag=1;
    IF EXISTS(SELECT 1 FROM #SGTraceFlags WHERE TraceFlag=2371 AND Status=1 AND [Global]=1) SET @DynamicFlag=1;

    BEGIN TRY
        -- Fail closed if configuration changed between dispatch and policy read,
        -- or a direct caller failed to establish the configured timeout.
        IF @LockTimeout IS NULL OR @@LOCK_TIMEOUT <> @LockTimeout
            THROW 51075, 'Configured lock timeout does not match the active execution scope. Call the public procedure; retry after configuration changes settle.', 1;
        IF @Mode='ENFORCE' AND @SelectedDatabaseCount>0
        BEGIN
            EXEC @LockResult=sys.sp_getapplock
                @Resource=N'DRE.StatsGovernance.v1.ENFORCE',@LockMode='Exclusive',
                @LockOwner='Session',@LockTimeout=0,@DbPrincipal='public';
            IF @LockResult<0 THROW 51038, 'Another enforcement run is active; this run did not start.', 1;
            SET @HaveAppLock=1;
        END;

        INSERT dbo.StatsGovernanceRuns
        (RunID,EngineVersion,Mode,StartedAtUTC,HeartbeatAtUTC,DeadlineUTC,SessionID,
         OriginalLogin,ServerName,ProductVersion,RequestedMAXDOP,ParametersXml,TraceFlagsXml,RunStatus)
        VALUES(@RunID,'1.3.2',@Mode,@StartedUTC,@StartedUTC,@DeadlineUTC,@@SPID,
         ORIGINAL_LOGIN(),CONVERT(sysname,SERVERPROPERTY('ServerName')),
         CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion')),@MAXDOP,@Policy,@TraceFlags,'RUNNING');
        SET @Progress=N'Governance RunID: '+CONVERT(nvarchar(36),@RunID);
        RAISERROR(N'%s',10,1,@Progress) WITH NOWAIT;
        INSERT dbo.StatsGovernanceRunDatabases
            (RunID,DatabaseName,CollectionStatus,DatabaseIDAtSelection,DatabaseCreateDateAtSelection,
             SelectionStatus,SelectionReason,ScopeAtSelectionXml,LastScopeStatus,ScopeAtLastCheckXml,LastScopeCheckAtUTC)
        SELECT @RunID,DatabaseName,CASE WHEN IsExcluded=1 THEN 'SKIPPED_EXCLUDED' ELSE 'PENDING' END,
            DatabaseID,DatabaseCreateDateLocal,SelectionStatus,SelectionReason,ScopeXml,
            CASE WHEN IsExcluded=1 THEN 'EXCLUDED' ELSE 'ALLOWED' END,ScopeXml,@StartedUTC
        FROM @DbList;

        CREATE TABLE #SGWork
        (
            WorkID int IDENTITY(1,1) NOT NULL PRIMARY KEY,
            FactsXml xml NOT NULL
        );
        DECLARE @WorkID int;
        DECLARE sg_db_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DatabaseName FROM @DbList WHERE IsExcluded=0 ORDER BY DatabaseName;
        OPEN sg_db_cursor;
        FETCH NEXT FROM sg_db_cursor INTO @Db;
        WHILE @@FETCH_STATUS=0
        BEGIN
            IF @DeadlineUTC IS NOT NULL AND SYSUTCDATETIME()>=@DeadlineUTC
            BEGIN
                SET @WindowExpired=1;
                BREAK;
            END;
            BEGIN TRY
                EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                IF @GateAllowed=0
                BEGIN
                    IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                    FETCH NEXT FROM sg_db_cursor INTO @Db;
                    CONTINUE;
                END;
                EXEC dbo.usp_DRE_StatsCollect_v1 @DatabaseName=@Db,
                    @LegacyTraceFlagVisible=@LegacyFlag,@ModernTraceFlagVisible=@ModernFlag,
                    @DynamicStatsTraceFlagGlobal=@DynamicFlag,@CapabilitiesXml=@Capabilities,
                    @TargetTablesXml=@TargetTablesXml,@StatisticsScope=@StatisticsScope,
                    @SnapshotXml=@StatsXml OUTPUT,@EnvironmentXml=@EnvXml OUTPUT;
                EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                IF @GateAllowed=0
                BEGIN
                    -- A scope change during a running metadata query is observed
                    -- here. Do not persist its application-statistic snapshots.
                    IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                    FETCH NEXT FROM sg_db_cursor INTO @Db;
                    CONTINUE;
                END;
                TRUNCATE TABLE #SGWork;
                INSERT #SGWork(FactsXml)
                    SELECT n.s.query('.') FROM @StatsXml.nodes('/Statistics/Statistic') AS n(s);
                UPDATE dbo.StatsGovernanceRunDatabases
                    SET CollectionStatus='COLLECTED',EnvironmentXml=@EnvXml,
                        CandidateCount=(SELECT COUNT(*) FROM #SGWork)
                    WHERE RunID=@RunID AND DatabaseName=@Db COLLATE Latin1_General_100_BIN2;
                WHILE EXISTS(SELECT 1 FROM #SGWork)
                BEGIN
                    IF @DeadlineUTC IS NOT NULL AND SYSUTCDATETIME()>=@DeadlineUTC
                    BEGIN
                        SET @WindowExpired=1;
                        UPDATE dbo.StatsGovernanceRunDatabases SET CollectionStatus='PARTIAL_WINDOW'
                        WHERE RunID=@RunID AND DatabaseName=@Db COLLATE Latin1_General_100_BIN2;
                        BREAK;
                    END;
                    EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                    IF @GateAllowed=0
                    BEGIN
                        IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                        UPDATE dbo.StatsGovernanceRunDatabases SET CollectionStatus='PARTIAL_SCOPE_CHANGE'
                        WHERE RunID=@RunID AND DatabaseName=@Db COLLATE Latin1_General_100_BIN2;
                        BREAK;
                    END;
                    SELECT TOP(1) @WorkID=WorkID,@Facts=FactsXml FROM #SGWork ORDER BY WorkID;
                    SELECT @Schema=@Facts.value('(/Statistic/SchemaName/text())[1]','nvarchar(128)'),
                           @Table=@Facts.value('(/Statistic/TableName/text())[1]','nvarchar(128)'),
                           @Stat=@Facts.value('(/Statistic/StatName/text())[1]','nvarchar(128)'),
                           @ObjectID=@Facts.value('(/Statistic/ObjectID/text())[1]','int'),
                           @StatsID=@Facts.value('(/Statistic/StatsID/text())[1]','int');
                    EXEC dbo.usp_DRE_StatsOverride_v1 @Db,@Schema,@Table,@Stat,@Override OUTPUT;
                    SELECT @Decision=(SELECT * FROM dbo.ufn_DRE_StatsDecision_v1(@Facts,@Policy,@Override)
                                      FOR XML PATH('Decision'),TYPE);
                    SELECT @Eligible=@Decision.value('(/Decision/IsEligible/text())[1]','bit'),
                           @Reason=@Decision.value('(/Decision/Reason/text())[1]','varchar(80)'),
                           @CanExecute=@Decision.value('(/Decision/CanExecute/text())[1]','bit'),
                           @CapabilityReason=CASE WHEN @Decision.exist('/Decision/CapabilityReason[1]')=1
                               THEN @Decision.value('(/Decision/CapabilityReason/text())[1]','varchar(80)') END,
                           @Method=(CASE WHEN @Decision.exist('/Decision/CollectionMethod[1]')=1 THEN @Decision.value('(/Decision/CollectionMethod/text())[1]','varchar(16)') END),
                           @Sample=(CASE WHEN @Decision.exist('/Decision/RequestedSamplePercent[1]')=1 THEN @Decision.value('(/Decision/RequestedSamplePercent/text())[1]','decimal(19,6)') END),
                           @SampleRows=(CASE WHEN @Decision.exist('/Decision/RequestedSampleRows[1]')=1 THEN @Decision.value('(/Decision/RequestedSampleRows/text())[1]','bigint') END),
                           @Persist=(CASE WHEN @Decision.exist('/Decision/PersistOption[1]')=1 THEN @Decision.value('(/Decision/PersistOption/text())[1]','bit') END),
                           @NoRecompute=@Facts.value('(/Statistic/NoRecompute/text())[1]','bit'),
                           @OverrideID=(CASE WHEN @Override.exist('/Override/OverrideID[1]')=1 THEN @Override.value('(/Override/OverrideID/text())[1]','int') END);
                    SET @Command=NULL;
                    IF @Mode<>'OBSERVE' AND @CanExecute=1
                    BEGIN
                        SET @Command=dbo.ufn_DRE_StatsCommand_v1(@Db,@Schema,@Table,@Stat,@Method,@Sample,@SampleRows,@Persist,@MAXDOP,@NoRecompute,@Capabilities);
                        IF @Command IS NULL THROW 51039, 'Command construction failed; no command was executed.', 1;
                    END;
                    INSERT dbo.StatsGovernanceTelemetry
                    (RunID,DatabaseName,SchemaName,TableName,StatName,ObjectID,StatsID,OverrideID,
                     InitialSnapshotXml,InitialOverrideXml,InitialDecisionXml,RecommendedCommand,ExecutionStatus,ExecutionReason)
                    VALUES(@RunID,@Db,@Schema,@Table,@Stat,@ObjectID,@StatsID,@OverrideID,
                        @Facts,@Override,@Decision,@Command,
                        CASE WHEN @Mode='OBSERVE' THEN 'OBSERVED'
                             WHEN @Eligible=0 THEN 'DEFERRED'
                             WHEN @CanExecute=0 THEN 'BLOCKED_CAPABILITY'
                             WHEN @Mode='RECOMMEND' THEN 'RECOMMENDED' ELSE 'PENDING' END,
                        CASE WHEN @Eligible=1 AND @CanExecute=0 THEN @CapabilityReason ELSE NULL END);
                    IF @Eligible=1 AND @CanExecute=0 SET @BlockedCount+=1;
                    DELETE #SGWork WHERE WorkID=@WorkID;
                END;
            END TRY
            BEGIN CATCH
                UPDATE dbo.StatsGovernanceRunDatabases
                SET CollectionStatus='FAILED',ErrorNumber=ERROR_NUMBER(),ErrorMessage=ERROR_MESSAGE()
                WHERE RunID=@RunID AND DatabaseName=@Db COLLATE Latin1_General_100_BIN2;
                -- Do not execute a partly collected database after a collection failure.
                UPDATE dbo.StatsGovernanceTelemetry
                SET ExecutionStatus='SKIPPED_COLLECTION_ERROR',ExecutionReason='DATABASE_COLLECTION_FAILED'
                WHERE RunID=@RunID AND DatabaseName=@Db COLLATE Latin1_General_100_BIN2 AND ExecutionStatus='PENDING';
                SET @FailedCount+=1;
            END CATCH;
            UPDATE dbo.StatsGovernanceRuns SET HeartbeatAtUTC=SYSUTCDATETIME() WHERE RunID=@RunID;
            FETCH NEXT FROM sg_db_cursor INTO @Db;
        END;
        CLOSE sg_db_cursor;
        DEALLOCATE sg_db_cursor;
        IF @WindowExpired=1
            UPDATE dbo.StatsGovernanceRunDatabases SET CollectionStatus='NOT_COLLECTED_WINDOW'
            WHERE RunID=@RunID AND CollectionStatus='PENDING';

        /* The only CommandLog DML and UPDATE STATISTICS execution are below
           this execution-only boundary. No fallback fake commands are logged. */
        IF @Mode='ENFORCE'
        BEGIN
            WHILE EXISTS(SELECT 1 FROM dbo.StatsGovernanceTelemetry WHERE RunID=@RunID AND ExecutionStatus='PENDING')
            BEGIN
                IF @DeadlineUTC IS NOT NULL AND SYSUTCDATETIME()>=@DeadlineUTC
                BEGIN
                    SET @WindowExpired=1;
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET ExecutionStatus='NOT_STARTED_WINDOW',ExecutionReason='MAINTENANCE_DEADLINE'
                    WHERE RunID=@RunID AND ExecutionStatus='PENDING';
                    BREAK;
                END;
                SELECT TOP(1) @TelemetryID=TelemetryID,@Db=DatabaseName,
                    @Schema=SchemaName,@Table=TableName,@Stat=StatName,@ObjectID=ObjectID,
                    @StatsID=StatsID,@Facts=InitialSnapshotXml
                FROM dbo.StatsGovernanceTelemetry
                WHERE RunID=@RunID AND ExecutionStatus='PENDING'
                ORDER BY TelemetryID;

                EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                IF @GateAllowed=0
                BEGIN
                    IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                    CONTINUE;
                END;
                SET @NewFacts=NULL;
                SET @CmdError=0;
                SET @CmdMessage=NULL;
                BEGIN TRY
                    EXEC dbo.usp_DRE_StatsCollect_v1 @DatabaseName=@Db,
                        @ObjectID=@ObjectID,@StatsID=@StatsID,@IncludeEnvironment=0,
                        @LegacyTraceFlagVisible=@LegacyFlag,@ModernTraceFlagVisible=@ModernFlag,
                        @DynamicStatsTraceFlagGlobal=@DynamicFlag,@CapabilitiesXml=@Capabilities,
                        @TargetTablesXml=@TargetTablesXml,@StatisticsScope=@StatisticsScope,
                        @SnapshotXml=@StatsXml OUTPUT,@EnvironmentXml=@EnvXml OUTPUT;
                    SET @NewFacts=@StatsXml.query('/Statistics/Statistic[1]');
                    IF @NewFacts.exist('/Statistic[1]')=0
                        THROW 51041, 'Statistic was dropped or is no longer visible; command skipped.', 1;
                    IF @NewFacts.value('(/Statistic/DatabaseID/text())[1]','int')
                         <>@Facts.value('(/Statistic/DatabaseID/text())[1]','int')
                       OR @NewFacts.value('(/Statistic/SchemaName/text())[1]','nvarchar(128)') COLLATE Latin1_General_100_BIN2
                         <>@Schema COLLATE Latin1_General_100_BIN2
                       OR @NewFacts.value('(/Statistic/TableName/text())[1]','nvarchar(128)') COLLATE Latin1_General_100_BIN2
                         <>@Table COLLATE Latin1_General_100_BIN2
                       OR @NewFacts.value('(/Statistic/StatName/text())[1]','nvarchar(128)') COLLATE Latin1_General_100_BIN2
                         <>@Stat COLLATE Latin1_General_100_BIN2
                       OR @NewFacts.value('(/Statistic/ObjectCreateDateLocal/text())[1]','datetime2(7)')
                         <>@Facts.value('(/Statistic/ObjectCreateDateLocal/text())[1]','datetime2(7)')
                        THROW 51042, 'Object identity/name changed since collection; command skipped.', 1;
                    EXEC dbo.usp_DRE_StatsOverride_v1 @Db,@Schema,@Table,@Stat,@Override OUTPUT;
                    SELECT @Decision=(SELECT * FROM dbo.ufn_DRE_StatsDecision_v1(@NewFacts,@Policy,@Override)
                                      FOR XML PATH('Decision'),TYPE);
                    SELECT @Eligible=@Decision.value('(/Decision/IsEligible/text())[1]','bit'),
                           @Reason=@Decision.value('(/Decision/Reason/text())[1]','varchar(80)'),
                           @CanExecute=@Decision.value('(/Decision/CanExecute/text())[1]','bit'),
                           @CapabilityReason=CASE WHEN @Decision.exist('/Decision/CapabilityReason[1]')=1
                               THEN @Decision.value('(/Decision/CapabilityReason/text())[1]','varchar(80)') END,
                           @Method=(CASE WHEN @Decision.exist('/Decision/CollectionMethod[1]')=1 THEN @Decision.value('(/Decision/CollectionMethod/text())[1]','varchar(16)') END),
                           @Sample=(CASE WHEN @Decision.exist('/Decision/RequestedSamplePercent[1]')=1 THEN @Decision.value('(/Decision/RequestedSamplePercent/text())[1]','decimal(19,6)') END),
                           @SampleRows=(CASE WHEN @Decision.exist('/Decision/RequestedSampleRows[1]')=1 THEN @Decision.value('(/Decision/RequestedSampleRows/text())[1]','bigint') END),
                           @Persist=(CASE WHEN @Decision.exist('/Decision/PersistOption[1]')=1 THEN @Decision.value('(/Decision/PersistOption/text())[1]','bit') END),
                           @NoRecompute=@NewFacts.value('(/Statistic/NoRecompute/text())[1]','bit');
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET RevalidatedSnapshotXml=@NewFacts,RevalidatedOverrideXml=@Override,
                        RevalidatedDecisionXml=@Decision,ExecutionReason=@Reason
                    WHERE TelemetryID=@TelemetryID;
                END TRY
                BEGIN CATCH
                    SET @CmdError=ERROR_NUMBER();
                    SET @CmdMessage=ERROR_MESSAGE();
                    SET @Eligible=0;
                    SET @FailedCount+=1;
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET ExecutionStatus='SKIPPED_REVALIDATION_ERROR',ErrorNumber=@CmdError,ErrorMessage=@CmdMessage
                    WHERE TelemetryID=@TelemetryID;
                END CATCH;

                IF @CmdError=0 AND @Eligible=0
                    UPDATE dbo.StatsGovernanceTelemetry SET ExecutionStatus='SKIPPED_REVALIDATED'
                    WHERE TelemetryID=@TelemetryID;

                IF @CmdError=0 AND @Eligible=1 AND @CanExecute=0
                BEGIN
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET ExecutionStatus='BLOCKED_CAPABILITY',ExecutionReason=@CapabilityReason
                    WHERE TelemetryID=@TelemetryID;
                    SET @BlockedCount+=1;
                END;
                IF @CmdError=0 AND @CanExecute=1
                BEGIN
                    SET @Command=dbo.ufn_DRE_StatsCommand_v1(@Db,@Schema,@Table,@Stat,@Method,@Sample,@SampleRows,@Persist,@MAXDOP,@NoRecompute,@Capabilities);
                    IF @Command IS NULL THROW 51043, 'Invalid revalidated command; stopping without executing it.', 1;
                    SELECT @IndexName=(CASE WHEN @NewFacts.exist('/Statistic/IndexName[1]')=1 THEN @NewFacts.value('(/Statistic/IndexName/text())[1]','nvarchar(128)') END),
                           @IndexType=(CASE WHEN @NewFacts.exist('/Statistic/IndexType[1]')=1 THEN @NewFacts.value('(/Statistic/IndexType/text())[1]','tinyint') END),
                           @ObjectType=@NewFacts.value('(/Statistic/ObjectType/text())[1]','char(2)');
                    SELECT @ExtendedInfo=(SELECT @RunID AS RunID,@TelemetryID AS TelemetryID,
                           'StatsGovernance-v1.3.2' AS Engine,@MAXDOP AS RequestedMAXDOP,
                           @Decision AS PolicyDecision,@NewFacts AS BeforeSnapshot
                           FOR XML PATH('StatisticsGovernance'),TYPE);

                    -- Last checkpoint before logging and starting a command.
                    IF @DeadlineUTC IS NOT NULL AND SYSUTCDATETIME()>=@DeadlineUTC
                        CONTINUE;
                    EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                    IF @GateAllowed=0
                    BEGIN
                        IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                        CONTINUE;
                    END;
                    INSERT dbo.CommandLog
                    (DatabaseName,SchemaName,ObjectName,ObjectType,IndexName,IndexType,
                     StatisticsName,PartitionNumber,ExtendedInfo,Command,CommandType,StartTime)
                    VALUES(@Db,@Schema,@Table,@ObjectType,@IndexName,@IndexType,
                         @Stat,NULL,@ExtendedInfo,@Command,N'UPDATE_STATISTICS',SYSDATETIME());
                    SET @LogID=CONVERT(int,SCOPE_IDENTITY());
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET CommandLogID=@LogID,ExecutedCommand=@Command,ExecutionStatus='EXECUTING'
                    WHERE TelemetryID=@TelemetryID;

                    SET @CmdStartedUTC=SYSUTCDATETIME();
                    SET @CmdError=0;
                    SET @CmdMessage=NULL;
                    BEGIN TRY
                        EXEC sys.sp_executesql @Command;
                    END TRY
                    BEGIN CATCH
                        SET @CmdError=ERROR_NUMBER();
                        SET @CmdMessage=ERROR_MESSAGE();
                    END CATCH;
                    SET @CmdEndedUTC=SYSUTCDATETIME();

                    -- Exactly this log row is finalized, including failures.
                    UPDATE dbo.CommandLog
                    SET EndTime=SYSDATETIME(),ErrorNumber=@CmdError,ErrorMessage=@CmdMessage
                    WHERE ID=@LogID;
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET ExecutionStatus=CASE WHEN @CmdError=0 THEN 'SUCCEEDED' ELSE 'FAILED' END,
                        CommandStartedAtUTC=@CmdStartedUTC,CommandEndedAtUTC=@CmdEndedUTC,
                        CommandElapsedMilliseconds=DATEDIFF_BIG(MILLISECOND,@CmdStartedUTC,@CmdEndedUTC),
                        ErrorNumber=@CmdError,ErrorMessage=@CmdMessage
                    WHERE TelemetryID=@TelemetryID;
                    IF @CmdError<>0 SET @FailedCount+=1;
                    ELSE
                    BEGIN
                        -- A postcheck failure must NOT cause the successful command to run again.
                        EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                        IF @GateAllowed=0
                        BEGIN
                            SET @PostcheckFailures+=1;
                            IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                            UPDATE dbo.StatsGovernanceTelemetry
                            SET PostcheckStatus='SKIPPED_SCOPE_CHANGE',PostcheckErrorMessage=@GateReason
                            WHERE TelemetryID=@TelemetryID;
                        END
                        ELSE
                        BEGIN
                        BEGIN TRY
                            EXEC dbo.usp_DRE_StatsCollect_v1 @DatabaseName=@Db,
                                @ObjectID=@ObjectID,@StatsID=@StatsID,@IncludeEnvironment=0,
                                @LegacyTraceFlagVisible=@LegacyFlag,@ModernTraceFlagVisible=@ModernFlag,
                                @DynamicStatsTraceFlagGlobal=@DynamicFlag,@CapabilitiesXml=@Capabilities,
                                @TargetTablesXml=@TargetTablesXml,@StatisticsScope=@StatisticsScope,
                                @SnapshotXml=@StatsXml OUTPUT,@EnvironmentXml=@EnvXml OUTPUT;
                            SET @NewFacts=@StatsXml.query('/Statistics/Statistic[1]');
                            SET @AfterPersist=CASE WHEN @NewFacts.exist('/Statistic/PersistedSamplePercent[1]')=1
                                THEN @NewFacts.value('(/Statistic/PersistedSamplePercent/text())[1]','decimal(19,6)') END;
                            SET @PostStatus=CASE
                                WHEN @NewFacts.exist('/Statistic[1]')=0 THEN 'STATISTIC_NOT_FOUND'
                                WHEN @NewFacts.exist('/Statistic/LastUpdatedLocal[1]')=0 THEN 'NO_STATISTICS_BLOB'
                                WHEN @Persist=1 AND (@AfterPersist IS NULL OR ABS(@AfterPersist-@Sample)>0.0001)
                                    THEN 'PERSISTENCE_VALIDATION_FAILED'
                                WHEN @Persist=0 AND (@AfterPersist IS NULL OR @AfterPersist<>0)
                                    THEN 'PERSISTENCE_VALIDATION_FAILED'
                                ELSE 'METADATA_COLLECTED' END;
                            IF @PostStatus<>'METADATA_COLLECTED' SET @PostcheckFailures+=1;
                            UPDATE dbo.StatsGovernanceTelemetry
                            SET AfterSnapshotXml=@NewFacts,PostcheckStatus=@PostStatus
                            WHERE TelemetryID=@TelemetryID;
                        END TRY
                        BEGIN CATCH
                            SET @PostcheckFailures+=1;
                            UPDATE dbo.StatsGovernanceTelemetry
                            SET PostcheckStatus='COLLECTION_FAILED',PostcheckErrorNumber=ERROR_NUMBER(),
                                PostcheckErrorMessage=ERROR_MESSAGE() WHERE TelemetryID=@TelemetryID;
                        END CATCH;
                        END;
                    END;
                END;
                UPDATE dbo.StatsGovernanceRuns SET HeartbeatAtUTC=SYSUTCDATETIME() WHERE RunID=@RunID;
                -- LOW means pacing, NOT lowering sample quality. HIGH does not
                -- increase concurrency: all tiers use a single worker in v1.
                IF @IOThroughputTier='LOW' AND EXISTS
                    (SELECT 1 FROM dbo.StatsGovernanceTelemetry WHERE RunID=@RunID AND ExecutionStatus='PENDING')
                    WAITFOR DELAY '00:00:01';
            END;
        END;

        SELECT @BlockedCount=COUNT(*)
        FROM dbo.StatsGovernanceTelemetry t JOIN dbo.StatsGovernanceRunDatabases d
            ON d.RunID=t.RunID AND d.DatabaseName COLLATE Latin1_General_100_BIN2=t.DatabaseName COLLATE Latin1_General_100_BIN2
        WHERE t.RunID=@RunID AND d.LastScopeStatus='ALLOWED'
            AND ((@Mode='ENFORCE' AND t.ExecutionStatus='BLOCKED_CAPABILITY')
              OR (@Mode<>'ENFORCE' AND t.InitialDecisionXml.value('(/Decision/IsEligible/text())[1]','bit')=1
                AND t.InitialDecisionXml.value('(/Decision/CanExecute/text())[1]','bit')=0));
        SET @RunStatus=CASE WHEN @FailedCount>0 THEN 'COMPLETED_WITH_ERRORS'
                            WHEN @SelectedDatabaseCount=0 THEN 'NO_DATABASES_TO_PROCESS'
                            WHEN @BlockedCount>0 THEN 'COMPLETED_WITH_BLOCKED_ACTIONS'
                            WHEN @WindowExpired=1 THEN 'WINDOW_EXPIRED'
                            WHEN @PostcheckFailures>0 THEN 'COMPLETED_WITH_WARNINGS'
                            ELSE 'COMPLETED' END;
        UPDATE dbo.StatsGovernanceRuns
        SET RunStatus=@RunStatus,FinishedAtUTC=SYSUTCDATETIME(),HeartbeatAtUTC=SYSUTCDATETIME()
        WHERE RunID=@RunID;
        IF @HaveAppLock=1
        BEGIN
            EXEC sys.sp_releaseapplock @Resource=N'DRE.StatsGovernance.v1.ENFORCE',
                @LockOwner='Session',@DbPrincipal='public';
            SET @HaveAppLock=0;
        END;
        -- The dispatcher batch owns LOCK_TIMEOUT; SQL Server restores it on exit.

        SELECT RunID,Mode,RunStatus,StartedAtUTC,FinishedAtUTC,RequestedMAXDOP,
               @FailedCount AS ErrorCount,@BlockedCount AS BlockedCapabilityCount,
               @PostcheckFailures AS PostcheckFailureCount,
               (SELECT COUNT(*) FROM @DbList) AS RequestedDatabaseCount,
               @SelectedDatabaseCount AS InitiallySelectedDatabaseCount,
               @InitialExcludedDatabaseCount AS InitiallyExcludedDatabaseCount,
               (SELECT COUNT(*) FROM dbo.StatsGovernanceRunDatabases
                 WHERE RunID=@RunID AND LastScopeStatus='EXCLUDED') AS ExcludedDatabaseCount
        FROM dbo.StatsGovernanceRuns WHERE RunID=@RunID;
        SELECT * FROM dbo.v_DRE_StatsGovernanceResults_v1 WHERE RunID=@RunID ORDER BY TelemetryID;
        SELECT * FROM dbo.v_DRE_StatsDatabaseSelection_v1 WHERE RunID=@RunID ORDER BY DatabaseName;
        IF @FailedCount>0
            THROW 51044, 'The run completed with errors. Inspect governance telemetry using the printed RunID.', 1;
        IF @Mode='ENFORCE' AND @BlockedCount>0
            THROW 51045, 'Eligible actions were blocked by build/capability checks. No unsupported commands were attempted. Review the RunID.',1;
    END TRY
    BEGIN CATCH
        DECLARE @OuterError int=ERROR_NUMBER(),@OuterMessage nvarchar(4000)=ERROR_MESSAGE();
        IF CURSOR_STATUS('local','sg_db_cursor')>=0 CLOSE sg_db_cursor;
        IF CURSOR_STATUS('local','sg_db_cursor')>=-1 DEALLOCATE sg_db_cursor;
        IF @HaveAppLock=1
            EXEC sys.sp_releaseapplock @Resource=N'DRE.StatsGovernance.v1.ENFORCE',
                @LockOwner='Session',@DbPrincipal='public';
        -- The dispatcher batch owns LOCK_TIMEOUT; SQL Server restores it on exit.
        UPDATE dbo.StatsGovernanceTelemetry
        SET ExecutionStatus='SKIPPED_RUN_ABORTED',ExecutionReason='RUN_ABORTED',
            ErrorNumber=@OuterError,ErrorMessage=@OuterMessage
        WHERE RunID=@RunID AND ExecutionStatus='PENDING';
        UPDATE dbo.StatsGovernanceRunDatabases SET CollectionStatus='NOT_COLLECTED_RUN_ABORTED'
        WHERE RunID=@RunID AND CollectionStatus='PENDING';
        UPDATE dbo.StatsGovernanceRuns
        SET RunStatus=CASE WHEN @OuterError=51044 THEN 'COMPLETED_WITH_ERRORS'
                           WHEN @OuterError=51045 THEN 'COMPLETED_WITH_BLOCKED_ACTIONS' ELSE 'FAILED' END,
            FinishedAtUTC=SYSUTCDATETIME(),HeartbeatAtUTC=SYSUTCDATETIME(),
            ErrorNumber=@OuterError,ErrorMessage=@OuterMessage WHERE RunID=@RunID;
        THROW;
    END CATCH;
END;
