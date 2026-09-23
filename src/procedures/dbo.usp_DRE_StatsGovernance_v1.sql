CREATE PROCEDURE dbo.usp_DRE_StatsGovernance_v1
    @Databases nvarchar(max),
    @Mode varchar(10) = 'RECOMMEND',
    @MAXDOP int = 4,
    @MinRowCountFloor bigint = 1000000,
    @LowSampleThresholdBase decimal(9,4) = 2.0,
    @LargeTableThresholdBase bigint = 20000000,
    @DefaultSamplePercentBase decimal(9,4) = NULL,
    @MaxExecutionTimeMinutes int = 300,
    @IOThroughputTier varchar(8) = 'STANDARD',
    @LegacyCEMultiplier decimal(9,4) = 2.0
AS
BEGIN
    -- Engine v1.3.2: scoped LOCK_TIMEOUT dispatcher. Public interface remains
    -- exactly ten parameters for backward compatibility. Table/statistics-scope
    -- targeting is exposed separately by usp_DRE_StatsGovernanceTargeted_v1.
    SET NOCOUNT ON;
    SET ROWCOUNT 0;
    IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1
        THROW 51020, 'v1 is an administrative procedure; execute as sysadmin or an authorized sysadmin-owned Agent job.', 1;
    IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
        THROW 51021, 'Run outside an explicit transaction with IMPLICIT_TRANSACTIONS OFF.', 1;

    DECLARE @LockTimeout int, @DispatchSql nvarchar(max), @ReturnCode int = 0;
    SELECT @LockTimeout = LockTimeoutMilliseconds
    FROM dbo.StatsGovernanceSettings
    WHERE SettingsID = 1 AND SchemaVersion = '1.3.0';
    IF @LockTimeout IS NULL OR @LockTimeout NOT BETWEEN 0 AND 600000
        THROW 51037, 'Missing/incompatible governance settings or lock timeout outside 0 through 600000 milliseconds.', 1;

    -- SET LOCK_TIMEOUT requires a numeric literal, not a local-variable operand.
    -- Only the validated integer is concatenated. Every public input remains a
    -- typed sp_executesql parameter. SET and worker execution stay in one batch.
    SET @DispatchSql = N'SET LOCK_TIMEOUT ' + CONVERT(nvarchar(11), @LockTimeout) + N';
EXEC @WorkerReturnCode = dbo.usp_DRE_StatsGovernanceWorker_v1
    @Databases = @pDatabases,
    @Mode = @pMode,
    @MAXDOP = @pMAXDOP,
    @MinRowCountFloor = @pMinRowCountFloor,
    @LowSampleThresholdBase = @pLowSampleThresholdBase,
    @LargeTableThresholdBase = @pLargeTableThresholdBase,
    @DefaultSamplePercentBase = @pDefaultSamplePercentBase,
    @MaxExecutionTimeMinutes = @pMaxExecutionTimeMinutes,
    @IOThroughputTier = @pIOThroughputTier,
    @LegacyCEMultiplier = @pLegacyCEMultiplier,
    @TargetTablesXml = NULL,
    @StatisticsScope = ''ALL'';';

    EXEC sys.sp_executesql @DispatchSql,
        N'@pDatabases nvarchar(max), @pMode varchar(10), @pMAXDOP int,
          @pMinRowCountFloor bigint, @pLowSampleThresholdBase decimal(9,4),
          @pLargeTableThresholdBase bigint, @pDefaultSamplePercentBase decimal(9,4),
          @pMaxExecutionTimeMinutes int, @pIOThroughputTier varchar(8),
          @pLegacyCEMultiplier decimal(9,4), @WorkerReturnCode int OUTPUT',
        @pDatabases = @Databases,
        @pMode = @Mode,
        @pMAXDOP = @MAXDOP,
        @pMinRowCountFloor = @MinRowCountFloor,
        @pLowSampleThresholdBase = @LowSampleThresholdBase,
        @pLargeTableThresholdBase = @LargeTableThresholdBase,
        @pDefaultSamplePercentBase = @DefaultSamplePercentBase,
        @pMaxExecutionTimeMinutes = @MaxExecutionTimeMinutes,
        @pIOThroughputTier = @IOThroughputTier,
        @pLegacyCEMultiplier = @LegacyCEMultiplier,
        @WorkerReturnCode = @ReturnCode OUTPUT;
    RETURN @ReturnCode;
END;
