CREATE PROCEDURE dbo.usp_DRE_StatsGovernanceTargeted_v1
    @Databases nvarchar(max),
    @Tables nvarchar(max) = NULL,
    @StatisticsScope varchar(20) = 'ALL',
    @Mode varchar(10) = 'RECOMMEND',
    @MAXDOP int = 4,
    @MinRowCountFloor bigint = 1000000,
    @MaxExecutionTimeMinutes int = 300,
    @IOThroughputTier varchar(8) = 'STANDARD'
AS
BEGIN
    /*
      Targeted public interface intentionally stays below ten parameters.
      Advanced policy knobs remain on dbo.usp_DRE_StatsGovernance_v1 and are
      fixed here to the documented v1.3 targeted defaults:
          LowSampleThresholdBase   = 2.0 percent
          LargeTableThresholdBase = 20,000,000 rows
          DefaultSamplePercentBase= NULL (SQL Server default unless policy/override chooses otherwise)
          LegacyCEMultiplier      = 2.0

      @Tables accepts a comma-separated list of two-part table names:
          schema.table,schema.table
      Bracketed two-part names are accepted by PARSENAME. A comma in an object
      name is not supported by this interface. When @Tables is supplied,
      @Databases must resolve to exactly one database and ALL is rejected.

      @StatisticsScope:
        ALL        = every supported statistic
        INDEX_ONLY = statistics associated with indexes
        AUTO_ONLY  = standalone auto-created statistics only
        USER_ONLY  = standalone user-created statistics only
        NON_AUTO   = every statistic that is not auto-created
    */
    SET NOCOUNT ON;
    SET ROWCOUNT 0;
    IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1
        THROW 51020, 'v1 is an administrative procedure; execute as sysadmin or an authorized sysadmin-owned Agent job.',1;
    IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2
        THROW 51021, 'Run outside an explicit transaction with IMPLICIT_TRANSACTIONS OFF.',1;

    SET @Databases=LTRIM(RTRIM(@Databases));
    SET @StatisticsScope=UPPER(LTRIM(RTRIM(@StatisticsScope)));
    SET @Tables=NULLIF(LTRIM(RTRIM(@Tables)),N'');
    SET @Mode=UPPER(LTRIM(RTRIM(@Mode)));
    SET @IOThroughputTier=UPPER(LTRIM(RTRIM(@IOThroughputTier)));
    IF @Databases IS NULL OR LEN(@Databases)=0
        THROW 51025, 'Specify one database, a comma-separated list, or ALL.',1;
    IF @StatisticsScope IS NULL OR @StatisticsScope NOT IN ('ALL','INDEX_ONLY','AUTO_ONLY','USER_ONLY','NON_AUTO')
        THROW 51120, 'StatisticsScope must be ALL, INDEX_ONLY, AUTO_ONLY, USER_ONLY, or NON_AUTO.',1;

    DECLARE @TargetTablesXml xml=NULL,@ResolvedDatabase sysname=NULL;
    IF @Tables IS NOT NULL
    BEGIN
        IF UPPER(@Databases)='ALL'
            THROW 51130, 'When @Tables is supplied, @Databases must name exactly one database; ALL is not allowed.',1;

        DECLARE @SelectionXml xml;
        EXEC dbo.usp_DRE_StatsDatabaseSelection_v1
            @Databases=@Databases,@SelectionXml=@SelectionXml OUTPUT,@EmitResult=0;
        IF @SelectionXml IS NULL OR @SelectionXml.value('count(/DatabaseSelection/Database)','int')<>1
            THROW 51131, 'When @Tables is supplied, @Databases must resolve to exactly one database.',1;
        SET @ResolvedDatabase=@SelectionXml.value('(/DatabaseSelection/Database/DatabaseName/text())[1]','nvarchar(128)');
        IF ISNULL(@SelectionXml.value('(/DatabaseSelection/Database/ReadyForCollection/text())[1]','bit'),0)<>1
            THROW 51132, 'The single targeted database must be online, accessible, non-snapshot, and ready for metadata resolution.',1;

        DECLARE @Compact nvarchar(max)=REPLACE(REPLACE(REPLACE(REPLACE(@Tables,N' ',N''),NCHAR(9),N''),NCHAR(13),N''),NCHAR(10),N'');
        IF LEFT(@Compact,1)=N',' OR RIGHT(@Compact,1)=N',' OR CHARINDEX(N',,',@Compact)>0
            THROW 51133, 'The @Tables list contains an empty item.',1;

        CREATE TABLE #RequestedTargets
        (
            SchemaName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            TableName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            PRIMARY KEY(SchemaName,TableName)
        );
        CREATE TABLE #CanonicalTargets
        (
            SchemaName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            TableName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            PRIMARY KEY(SchemaName,TableName)
        );
        CREATE TABLE #MissingTargets
        (
            SchemaName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            TableName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            PRIMARY KEY(SchemaName,TableName)
        );

        DECLARE @TableTokens TABLE(Token nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL);
        DECLARE @TokenStart int=1,@TokenEnd int;
        WHILE 1=1
        BEGIN
            SET @TokenEnd=CHARINDEX(N',',@Tables,@TokenStart);
            IF @TokenEnd=0
            BEGIN
                INSERT @TableTokens(Token) VALUES(LTRIM(RTRIM(SUBSTRING(@Tables,@TokenStart,LEN(@Tables)-@TokenStart+1))));
                BREAK;
            END;
            INSERT @TableTokens(Token) VALUES(LTRIM(RTRIM(SUBSTRING(@Tables,@TokenStart,@TokenEnd-@TokenStart))));
            SET @TokenStart=@TokenEnd+1;
        END;

        DECLARE @BadToken nvarchar(4000)=NULL;
        SELECT TOP(1) @BadToken=Token
        FROM @TableTokens
        WHERE PARSENAME(Token,1) IS NULL
           OR PARSENAME(Token,2) IS NULL
           OR PARSENAME(Token,3) IS NOT NULL
           OR PARSENAME(Token,4) IS NOT NULL;
        IF @BadToken IS NOT NULL
            THROW 51134, 'Every @Tables item must be a valid two-part schema.table identifier.',1;

        INSERT #RequestedTargets(SchemaName,TableName)
        SELECT DISTINCT CONVERT(sysname,PARSENAME(Token,2)),
                        CONVERT(sysname,PARSENAME(Token,1))
        FROM @TableTokens;
        IF NOT EXISTS(SELECT 1 FROM #RequestedTargets)
            THROW 51135, 'No table targets were parsed from @Tables.',1;

        DECLARE @ResolveSql nvarchar(max)=N'USE '+QUOTENAME(@ResolvedDatabase)+N';
INSERT #MissingTargets(SchemaName,TableName)
SELECT r.SchemaName,r.TableName
FROM #RequestedTargets AS r
WHERE NOT EXISTS
(
    SELECT 1
    FROM sys.tables AS t
    JOIN sys.schemas AS s ON s.schema_id=t.schema_id
    WHERE t.is_ms_shipped=0 AND t.is_external=0
      AND s.name COLLATE DATABASE_DEFAULT=r.SchemaName COLLATE DATABASE_DEFAULT
      AND t.name COLLATE DATABASE_DEFAULT=r.TableName COLLATE DATABASE_DEFAULT
);
INSERT #CanonicalTargets(SchemaName,TableName)
SELECT DISTINCT s.name,t.name
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id=t.schema_id
JOIN #RequestedTargets AS r
  ON s.name COLLATE DATABASE_DEFAULT=r.SchemaName COLLATE DATABASE_DEFAULT
 AND t.name COLLATE DATABASE_DEFAULT=r.TableName COLLATE DATABASE_DEFAULT
WHERE t.is_ms_shipped=0 AND t.is_external=0;';
        EXEC sys.sp_executesql @ResolveSql;

        IF EXISTS(SELECT 1 FROM #MissingTargets)
        BEGIN
            DECLARE @MissingSchema sysname,@MissingTable sysname,@MissingMessage nvarchar(2048);
            SELECT TOP(1) @MissingSchema=SchemaName,@MissingTable=TableName
            FROM #MissingTargets ORDER BY SchemaName,TableName;
            SET @MissingMessage=N'Target table not found: '+QUOTENAME(@ResolvedDatabase)+N'.'+QUOTENAME(@MissingSchema)+N'.'+QUOTENAME(@MissingTable)+N'.';
            THROW 51136,@MissingMessage,1;
        END;

        SELECT @TargetTablesXml=
        (
            SELECT @ResolvedDatabase AS DatabaseName,
                   (SELECT SchemaName,TableName FROM #CanonicalTargets ORDER BY SchemaName,TableName FOR XML PATH('Table'),TYPE)
            FOR XML PATH('TableTargets'),TYPE
        );
        IF @TargetTablesXml IS NULL OR @TargetTablesXml.exist('/TableTargets/Table[1]')<>1
            THROW 51137, 'Canonical target-table resolution returned no tables.',1;
    END;

    -- Keep the targeted interface operationally compact. These four advanced
    -- controls use the same documented defaults as the legacy public procedure.
    DECLARE @LowSampleThresholdBase decimal(9,4)=2.0,
            @LargeTableThresholdBase bigint=20000000,
            @DefaultSamplePercentBase decimal(9,4)=NULL,
            @LegacyCEMultiplier decimal(9,4)=2.0;

    DECLARE @LockTimeout int,@DispatchSql nvarchar(max),@ReturnCode int=0;
    SELECT @LockTimeout=LockTimeoutMilliseconds
    FROM dbo.StatsGovernanceSettings
    WHERE SettingsID=1 AND SchemaVersion='1.3.0';
    IF @LockTimeout IS NULL OR @LockTimeout NOT BETWEEN 0 AND 600000
        THROW 51037, 'Missing/incompatible governance settings or lock timeout outside 0 through 600000 milliseconds.',1;

    SET @DispatchSql=N'SET LOCK_TIMEOUT '+CONVERT(nvarchar(11),@LockTimeout)+N';
EXEC @WorkerReturnCode = dbo.usp_DRE_StatsGovernanceWorker_v1
    @Databases=@pDatabases,
    @Mode=@pMode,
    @MAXDOP=@pMAXDOP,
    @MinRowCountFloor=@pMinRowCountFloor,
    @LowSampleThresholdBase=@pLowSampleThresholdBase,
    @LargeTableThresholdBase=@pLargeTableThresholdBase,
    @DefaultSamplePercentBase=@pDefaultSamplePercentBase,
    @MaxExecutionTimeMinutes=@pMaxExecutionTimeMinutes,
    @IOThroughputTier=@pIOThroughputTier,
    @LegacyCEMultiplier=@pLegacyCEMultiplier,
    @TargetTablesXml=@pTargetTablesXml,
    @StatisticsScope=@pStatisticsScope;';

    EXEC sys.sp_executesql @DispatchSql,
        N'@pDatabases nvarchar(max),@pMode varchar(10),@pMAXDOP int,
          @pMinRowCountFloor bigint,@pLowSampleThresholdBase decimal(9,4),
          @pLargeTableThresholdBase bigint,@pDefaultSamplePercentBase decimal(9,4),
          @pMaxExecutionTimeMinutes int,@pIOThroughputTier varchar(8),
          @pLegacyCEMultiplier decimal(9,4),@pTargetTablesXml xml,
          @pStatisticsScope varchar(20),@WorkerReturnCode int OUTPUT',
        @pDatabases=@Databases,@pMode=@Mode,@pMAXDOP=@MAXDOP,
        @pMinRowCountFloor=@MinRowCountFloor,@pLowSampleThresholdBase=@LowSampleThresholdBase,
        @pLargeTableThresholdBase=@LargeTableThresholdBase,@pDefaultSamplePercentBase=@DefaultSamplePercentBase,
        @pMaxExecutionTimeMinutes=@MaxExecutionTimeMinutes,@pIOThroughputTier=@IOThroughputTier,
        @pLegacyCEMultiplier=@LegacyCEMultiplier,@pTargetTablesXml=@TargetTablesXml,
        @pStatisticsScope=@StatisticsScope,@WorkerReturnCode=@ReturnCode OUTPUT;
    RETURN @ReturnCode;
END;
