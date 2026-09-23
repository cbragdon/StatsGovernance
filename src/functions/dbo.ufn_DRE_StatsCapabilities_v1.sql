CREATE FUNCTION dbo.ufn_DRE_StatsCapabilities_v1
(
    @ProductVersion nvarchar(128), @EngineEdition int
)
RETURNS @Capabilities TABLE
(
    ProductMajorVersion int NULL, ProductMinorVersion int NULL,
    ProductBuild int NULL, ProductRevision int NULL, EngineEdition int NULL,
    SupportedEngine bit NOT NULL, BuildRuleStatus varchar(64) NOT NULL,
    SupportsCreateOrAlter bit NULL, SupportsStatisticsMAXDOP bit NULL,
    SupportsPersistSamplePercent bit NULL,
    PreservesPersistedSampleAfterRebuild bit NULL,
    SupportsStatsHistogramDMF bit NULL,
    SupportsQueryStore bit NULL, SupportsQueryStoreWaitStats bit NULL,
    SupportsCEFeedback bit NULL
)
AS
BEGIN
    DECLARE @Major int=TRY_CONVERT(int,PARSENAME(@ProductVersion,4)),
            @Minor int=TRY_CONVERT(int,PARSENAME(@ProductVersion,3)),
            @Build int=TRY_CONVERT(int,PARSENAME(@ProductVersion,2)),
            @Revision int=TRY_CONVERT(int,PARSENAME(@ProductVersion,1)),
            @Supported bit=0, @Rule varchar(64)='UNRECOGNIZED_ENGINE_OR_VERSION',
            @CreateAlter bit, @Maxdop bit, @Persist bit, @Rebuild bit,
            @Histogram bit, @QS bit, @QSWait bit, @CE bit;

    IF @EngineEdition=8
    BEGIN
        SELECT @Supported=1,@Rule='MANAGED_INSTANCE_SERVICE_CAPABILITIES',
               @CreateAlter=1,@Maxdop=1,@Persist=1,@Rebuild=1,@Histogram=1,
               @QS=1,@QSWait=1,@CE=NULL;
    END
    ELSE IF @EngineEdition IN (2,3,4) AND @Major IN (13,14,15,16,17)
        AND @Minor=0 AND @Build IS NOT NULL AND @Revision IS NOT NULL
        AND @Build>=0 AND @Revision>=0
        AND LEN(@ProductVersion)-LEN(REPLACE(@ProductVersion,N'.',N''))=3
        AND ((@Major=13 AND @Build>=1601) OR (@Major=14 AND @Build>=1000)
          OR (@Major=15 AND @Build>=2000) OR (@Major IN (16,17) AND @Build>=1000))
    BEGIN
        SELECT @Supported=1,@Rule='DOCUMENTED_BUILD_RULES',@QS=1,
               @QSWait=CASE WHEN @Major>=14 THEN 1 ELSE 0 END,
               @CE=CASE WHEN @Major>=16 THEN 1 ELSE 0 END;
        IF @Major=13
            SELECT @CreateAlter=CASE WHEN @Build>=4001 THEN 1 ELSE 0 END,
                   @Maxdop=CASE WHEN @Build>=5026 THEN 1 ELSE 0 END,
                   @Persist=CASE WHEN @Build>=5026 OR (@Build>=4446 AND @Build<5000) THEN 1 ELSE 0 END,
                   @Rebuild=CASE WHEN @Build>=6300 OR
                       (@Build<6000 AND (@Build>5888 OR (@Build=5888 AND @Revision>=11)))
                       THEN 1 ELSE 0 END,
                   -- sys.dm_db_stats_histogram starts with SQL Server 2016 SP1 CU2 (13.0.4422.0).
                   -- Later SP branches have the feature. RTM/GDR branches below SP1 CU2 do not.
                   @Histogram=CASE WHEN @Build>=5000 OR @Build>=4422 THEN 1 ELSE 0 END;
        ELSE IF @Major=14
            SELECT @CreateAlter=1,
                   @Maxdop=CASE WHEN @Build>3015 OR (@Build=3015 AND @Revision>=40) THEN 1 ELSE 0 END,
                   @Persist=CASE WHEN @Build>3006 OR (@Build=3006 AND @Revision>=16) THEN 1 ELSE 0 END,
                   @Rebuild=CASE WHEN @Build>3411 OR (@Build=3411 AND @Revision>=3) THEN 1 ELSE 0 END,
                   @Histogram=1;
        ELSE IF @Major=15
            SELECT @CreateAlter=1,@Maxdop=1,@Persist=1,@Histogram=1,
                   @Rebuild=CASE WHEN @Build>4123 OR (@Build=4123 AND @Revision>=1) THEN 1 ELSE 0 END;
        ELSE SELECT @CreateAlter=1,@Maxdop=1,@Persist=1,@Rebuild=1,@Histogram=1;
    END;
    INSERT @Capabilities VALUES
        (@Major,@Minor,@Build,@Revision,@EngineEdition,@Supported,@Rule,
         @CreateAlter,@Maxdop,@Persist,@Rebuild,@Histogram,@QS,@QSWait,@CE);
    RETURN;
END;
