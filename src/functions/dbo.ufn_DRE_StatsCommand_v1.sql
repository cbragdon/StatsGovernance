CREATE FUNCTION dbo.ufn_DRE_StatsCommand_v1
(
    @DatabaseName sysname, @SchemaName sysname, @TableName sysname,
    @StatName sysname, @Method varchar(16), @SamplePercent decimal(19,6),
    @SampleRows bigint, @PersistOption bit, @MAXDOP int, @NoRecompute bit,
    @Capabilities xml
)
RETURNS nvarchar(max)
AS
BEGIN
    IF @DatabaseName IS NULL OR @SchemaName IS NULL OR @TableName IS NULL
       OR @StatName IS NULL OR @MAXDOP IS NULL OR @MAXDOP NOT BETWEEN 1 AND 64
       OR @Method IS NULL OR @Method NOT IN ('AUTO','SAMPLE_PERCENT','SAMPLE_ROWS','FULLSCAN')
        RETURN NULL;
    IF @Method='SAMPLE_PERCENT' AND (@SamplePercent IS NULL OR @SamplePercent<=0 OR @SamplePercent>100)
        RETURN NULL;
    IF @Method='SAMPLE_ROWS' AND (@SampleRows IS NULL OR @SampleRows<=0)
        RETURN NULL;
    IF @Method<>'SAMPLE_PERCENT' AND @SamplePercent IS NOT NULL AND @Method<>'FULLSCAN' RETURN NULL;
    IF @Method<>'SAMPLE_ROWS' AND @SampleRows IS NOT NULL RETURN NULL;

    DECLARE @CanMaxdop bit=CASE WHEN @Capabilities.exist('/Capabilities/SupportsStatisticsMAXDOP[1]')=1
        THEN @Capabilities.value('(/Capabilities/SupportsStatisticsMAXDOP/text())[1]','bit') END,
        @CanPersist bit=CASE WHEN @Capabilities.exist('/Capabilities/SupportsPersistSamplePercent[1]')=1
        THEN @Capabilities.value('(/Capabilities/SupportsPersistSamplePercent/text())[1]','bit') END,
        @HasMetadata bit=CASE WHEN @Capabilities.exist('/Capabilities/HasPersistedSamplePercentMetadata[1]')=1
        THEN @Capabilities.value('(/Capabilities/HasPersistedSamplePercentMetadata/text())[1]','bit') END;
    IF ISNULL(@CanMaxdop,0)<>1 RETURN NULL;
    IF @PersistOption IS NOT NULL
    BEGIN
        IF ISNULL(@CanPersist,0)<>1 OR ISNULL(@HasMetadata,0)<>1 RETURN NULL;
    END;
    IF @Method='AUTO' AND @PersistOption IS NOT NULL RETURN NULL;

    DECLARE @Command nvarchar(max)=N'USE '+QUOTENAME(@DatabaseName)
        +N'; UPDATE STATISTICS '+QUOTENAME(@SchemaName)+N'.'+QUOTENAME(@TableName)
        +N' ('+QUOTENAME(@StatName)+N') WITH ';
    IF @Method='FULLSCAN' SET @Command+=N'FULLSCAN, ';
    IF @Method='SAMPLE_PERCENT'
        SET @Command+=N'SAMPLE '+CONVERT(nvarchar(32),@SamplePercent)+N' PERCENT, ';
    IF @Method='SAMPLE_ROWS'
        SET @Command+=N'SAMPLE '+CONVERT(nvarchar(32),@SampleRows)+N' ROWS, ';
    IF @PersistOption IS NOT NULL
        SET @Command+=N'PERSIST_SAMPLE_PERCENT = '+CASE WHEN @PersistOption=1 THEN N'ON' ELSE N'OFF' END+N', ';
    SET @Command+=N'MAXDOP = '+CONVERT(nvarchar(10),@MAXDOP);
    IF @NoRecompute=1 SET @Command+=N', NORECOMPUTE';
    RETURN @Command+N';';
END;
