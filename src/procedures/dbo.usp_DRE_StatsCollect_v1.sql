CREATE PROCEDURE dbo.usp_DRE_StatsCollect_v1
    @DatabaseName sysname,
    @ObjectID int = NULL,
    @StatsID int = NULL,
    @IncludeEnvironment bit = 1,
    @LegacyTraceFlagVisible bit = 0,
    @SnapshotXml xml = NULL OUTPUT,
    @EnvironmentXml xml = NULL OUTPUT,
    @CapabilitiesXml xml = NULL,
    @ModernTraceFlagVisible bit = 0,
    @DynamicStatsTraceFlagGlobal bit = 0,
    @TargetTablesXml xml = NULL,
    @StatisticsScope varchar(20) = 'ALL'
AS
BEGIN
    SET NOCOUNT ON;
    SET @SnapshotXml=NULL;
    SET @EnvironmentXml=NULL;
    SET @StatisticsScope=UPPER(LTRIM(RTRIM(@StatisticsScope)));
    IF DB_ID(@DatabaseName) IS NULL THROW 51010,'Target database does not exist or is not visible.',1;
    IF @StatisticsScope IS NULL OR @StatisticsScope NOT IN ('ALL','INDEX_ONLY','AUTO_ONLY','USER_ONLY','NON_AUTO')
        THROW 51120,'StatisticsScope must be ALL, INDEX_ONLY, AUTO_ONLY, USER_ONLY, or NON_AUTO.',1;

    IF @CapabilitiesXml IS NULL
        EXEC dbo.usp_DRE_StatsCapabilities_v1 @CapabilitiesXml=@CapabilitiesXml OUTPUT,@EmitResult=0;
    DECLARE @HasMetadata bit=CASE WHEN @CapabilitiesXml.exist('/Capabilities/HasPersistedSamplePercentMetadata[1]')=1
                THEN @CapabilitiesXml.value('(/Capabilities/HasPersistedSamplePercentMetadata/text())[1]','bit') END,
            @SupportsPersist bit=CASE WHEN @CapabilitiesXml.exist('/Capabilities/SupportsPersistSamplePercent[1]')=1
                THEN @CapabilitiesXml.value('(/Capabilities/SupportsPersistSamplePercent/text())[1]','bit') END,
            @SupportsHistogram bit=CASE WHEN @CapabilitiesXml.exist('/Capabilities/SupportsStatsHistogramDMF[1]')=1
                THEN @CapabilitiesXml.value('(/Capabilities/SupportsStatsHistogramDMF/text())[1]','bit') END;
    IF ISNULL(@CapabilitiesXml.value('(/Capabilities/SupportedEngine/text())[1]','bit'),0)<>1
        THROW 51011,'Unrecognized engine/build for metadata collection.',1;

    DECLARE @HistogramSelect nvarchar(max),@HistogramApply nvarchar(max);
    IF @SupportsHistogram=1
    BEGIN
        SET @HistogramSelect=N'
                h.HistogramObservedSteps,h.HistogramEstimatedRows,
                h.HistogramMaxEqualityRows,h.HistogramMaxRangeRows,h.HistogramTop3EqualityRows,
                CONVERT(decimal(19,6),100.0*h.HistogramMaxEqualityRows/NULLIF(h.HistogramEstimatedRows,0)) AS HistogramDominantEqualityPercent,
                CONVERT(decimal(19,6),100.0*h.HistogramTop3EqualityRows/NULLIF(h.HistogramEstimatedRows,0)) AS HistogramTop3EqualityPercent,
                CASE WHEN sp.object_id IS NULL THEN ''STATISTICS_PROPERTIES_UNAVAILABLE''
                     WHEN ISNULL(h.HistogramObservedSteps,0)=0 THEN ''NO_HISTOGRAM_ROWS''
                     ELSE ''AVAILABLE'' END AS HistogramAnalysisStatus,';
        SET @HistogramApply=N'
            OUTER APPLY
            (
                SELECT COUNT_BIG(*) AS HistogramObservedSteps,
                    CONVERT(decimal(38,6),SUM(CONVERT(decimal(38,6),ISNULL(hg.equal_rows,0)+ISNULL(hg.range_rows,0)))) AS HistogramEstimatedRows,
                    CONVERT(decimal(38,6),MAX(ISNULL(hg.equal_rows,0))) AS HistogramMaxEqualityRows,
                    CONVERT(decimal(38,6),MAX(ISNULL(hg.range_rows,0))) AS HistogramMaxRangeRows,
                    CONVERT(decimal(38,6),(SELECT SUM(CONVERT(decimal(38,6),x.equal_rows))
                       FROM (SELECT TOP (3) h3.equal_rows
                             FROM sys.dm_db_stats_histogram(s.object_id,s.stats_id) AS h3
                             ORDER BY h3.equal_rows DESC) AS x)) AS HistogramTop3EqualityRows
                FROM sys.dm_db_stats_histogram(s.object_id,s.stats_id) AS hg
            ) AS h';
    END
    ELSE
    BEGIN
        SET @HistogramSelect=N'
                CONVERT(bigint,NULL) AS HistogramObservedSteps,
                CONVERT(decimal(38,6),NULL) AS HistogramEstimatedRows,
                CONVERT(decimal(38,6),NULL) AS HistogramMaxEqualityRows,
                CONVERT(decimal(38,6),NULL) AS HistogramMaxRangeRows,
                CONVERT(decimal(38,6),NULL) AS HistogramTop3EqualityRows,
                CONVERT(decimal(19,6),NULL) AS HistogramDominantEqualityPercent,
                CONVERT(decimal(19,6),NULL) AS HistogramTop3EqualityPercent,
                CASE WHEN @HistogramCap=0 THEN ''NOT_SUPPORTED_ON_THIS_BUILD'' ELSE ''CAPABILITY_UNKNOWN'' END AS HistogramAnalysisStatus,';
        SET @HistogramApply=N'';
    END;

    DECLARE @Sql nvarchar(max)=N'USE '+QUOTENAME(@DatabaseName)+N';
        DECLARE @CapturedUTC datetime2(7)=SYSUTCDATETIME();
        DECLARE @CapturedLocal datetime2(7)=SYSDATETIME();
        DECLARE @Compat int=(SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID());
        DECLARE @ScopedLegacy bit=(SELECT CONVERT(bit,value) FROM sys.database_scoped_configurations WHERE name=N''LEGACY_CARDINALITY_ESTIMATION'');
        DECLARE @Major int=@Caps.value(''(/Capabilities/ProductMajorVersion/text())[1]'',''int'');
        DECLARE @EngineEdition int=@Caps.value(''(/Capabilities/EngineEdition/text())[1]'',''int'');
        DECLARE @QSState nvarchar(60)=(SELECT actual_state_desc FROM sys.database_query_store_options);
        DECLARE @AutoUpdateStats bit=(SELECT is_auto_update_stats_on FROM sys.databases WHERE database_id=DB_ID());
        DECLARE @AutoUpdateStatsAsync bit=(SELECT is_auto_update_stats_async_on FROM sys.databases WHERE database_id=DB_ID());
        DECLARE @CEFeedbackSetting bit=(SELECT CONVERT(bit,value) FROM sys.database_scoped_configurations WHERE name=N''CE_FEEDBACK'');
        DECLARE @Legacy bit=CASE WHEN @LegacyFlag=1 AND @ModernFlag=1 THEN NULL WHEN @ModernFlag=1 THEN 0
            WHEN @Compat<120 OR @ScopedLegacy=1 OR @LegacyFlag=1 THEN 1 ELSE 0 END;
        DECLARE @SamplingScanBehavior varchar(100)=CASE
            WHEN @EngineEdition=8 OR @Major>=14 THEN ''SERIAL_SAMPLING_SCAN_OTHER_OPERATORS_MAY_PARALLELIZE''
            WHEN @Major=13 AND @Compat=130 THEN ''PARALLEL_SAMPLING_SCAN_POSSIBLE''
            ELSE ''SERIAL_SAMPLING_SCAN'' END;
        -- Updateability reports READ_ONLY on SQL Server AG secondaries and
        -- Azure SQL Managed Instance read-only replicas.
        DECLARE @Writable bit=CASE WHEN DATABASEPROPERTYEX(DB_NAME(),''Updateability'')=''READ_WRITE''
               THEN 1 ELSE 0 END;
        DECLARE @Targets TABLE(SchemaName sysname COLLATE DATABASE_DEFAULT NOT NULL,TableName sysname COLLATE DATABASE_DEFAULT NOT NULL,
                               PRIMARY KEY(SchemaName,TableName));
        IF @TargetTables IS NOT NULL
            INSERT @Targets(SchemaName,TableName)
            SELECT T.n.value(''(SchemaName/text())[1]'',''nvarchar(128)''),T.n.value(''(TableName/text())[1]'',''nvarchar(128)'')
            FROM @TargetTables.nodes(''/TableTargets/Table'') AS T(n);

        ;WITH RowTotals AS
        (
            SELECT object_id,SUM(row_count) AS CurrentTableRows,COUNT_BIG(*) AS BasePartitionCount
            FROM sys.dm_db_partition_stats WHERE index_id IN(0,1) AND (@OID IS NULL OR object_id=@OID)
            GROUP BY object_id
        )
        SELECT @Out=(SELECT @CapturedUTC AS CapturedAtUTC,@CapturedLocal AS CapturedAtLocal,
                DB_ID() AS DatabaseID,DB_NAME() AS DatabaseName,t.object_id AS ObjectID,t.create_date AS ObjectCreateDateLocal,
                s.stats_id AS StatsID,sch.name AS SchemaName,t.name AS TableName,s.name AS StatName,t.type AS ObjectType,
                i.name AS IndexName,i.type AS IndexType,i.type_desc AS IndexTypeDescription,
                CASE WHEN i.index_id IS NULL THEN ''STANDALONE''
                     WHEN i.type IN(1,2) THEN ''ROWSTORE'' WHEN i.type=3 THEN ''XML'' WHEN i.type=4 THEN ''SPATIAL''
                     WHEN i.type IN(5,6) THEN ''COLUMNSTORE'' WHEN i.type=7 THEN ''HASH'' WHEN i.type=9 THEN ''JSON'' ELSE ''UNKNOWN'' END AS IndexFamily,
                CASE WHEN i.index_id IS NOT NULL THEN ''INDEX_ASSOCIATED''
                     WHEN EXISTS(SELECT 1 FROM sys.indexes ci2 WHERE ci2.object_id=t.object_id AND ci2.type IN(5,6))
                         THEN ''STANDALONE_ON_TABLE_WITH_COLUMNSTORE'' ELSE ''STANDALONE'' END AS StatisticsContext,
                ISNULL(i.is_disabled,0) AS IndexDisabled,ISNULL(i.is_hypothetical,0) AS IndexHypothetical,ISNULL(b.is_disabled,0) AS BaseIndexDisabled,
                CASE WHEN b.type=5 THEN ''CLUSTERED_COLUMNSTORE'' WHEN b.type=1 THEN ''CLUSTERED_ROWSTORE'' ELSE ''HEAP'' END AS BaseStorage,
                CONVERT(bit,CASE WHEN EXISTS(SELECT 1 FROM sys.indexes ci WHERE ci.object_id=t.object_id AND ci.type IN(5,6)) THEN 1 ELSE 0 END) AS HasColumnstore,
                t.is_memory_optimized AS IsMemoryOptimized,s.auto_created AS AutoCreated,s.user_created AS UserCreated,
                CASE WHEN i.index_id IS NOT NULL THEN ''Index'' WHEN s.auto_created=1 THEN ''AutoCreated'' ELSE ''UserCreated'' END AS StatisticType,
                s.no_recompute AS NoRecompute,s.is_temporary AS IsTemporary,s.is_incremental AS IsIncremental,s.has_filter AS HasFilter,
                s.filter_definition AS FilterDefinition,c.name AS LeadingColumnName,TYPE_NAME(c.system_type_id) AS LeadingColumnDataType,
                c.max_length AS LeadingColumnMaxLengthBytes,c.is_identity AS LeadingColumnIsIdentity,rt.CurrentTableRows,rt.BasePartitionCount,
                CONVERT(bit,CASE WHEN sp.object_id IS NULL THEN 0 ELSE 1 END) AS StatsPropertiesAvailable,
                sp.rows AS StatsRows,sp.rows_sampled AS RowsSampled,sp.unfiltered_rows AS UnfilteredRowsAtLastUpdate,
                sp.last_updated AS LastUpdatedLocal,DATEDIFF_BIG(MINUTE,sp.last_updated,@CapturedLocal) AS StatsAgeMinutes,
                sp.modification_counter AS ModificationCounter,
                TRY_CONVERT(bigint,CONVERT(decimal(38,0),rt.CurrentTableRows)-CONVERT(decimal(38,0),COALESCE(sp.unfiltered_rows,sp.rows))) AS RowCountDeltaSinceStatsUpdate,
                nt.AutoUpdateThresholdBasisRows,
                nt.EstimatedAutoUpdateThresholdModifications,
                nt.EstimatedAutoUpdateThresholdModifications AS EstimatedNextAutoUpdateAtModificationCounter,
                CONVERT(bit,CASE WHEN nt.EstimatedAutoUpdateThresholdModifications IS NULL THEN 0 ELSE 1 END) AS AutoUpdateThresholdIsEstimate,
                CASE WHEN nt.EstimatedAutoUpdateThresholdModifications IS NULL OR sp.modification_counter IS NULL THEN NULL
                     WHEN sp.modification_counter>=nt.EstimatedAutoUpdateThresholdModifications THEN CONVERT(bigint,0)
                     ELSE nt.EstimatedAutoUpdateThresholdModifications-sp.modification_counter END AS EstimatedModificationsRemainingToAutoUpdate,
                CASE WHEN nt.EstimatedAutoUpdateThresholdModifications IS NULL OR nt.EstimatedAutoUpdateThresholdModifications=0 OR sp.modification_counter IS NULL THEN NULL
                     ELSE CONVERT(decimal(19,6),CONVERT(decimal(38,6),sp.modification_counter)*100.0/nt.EstimatedAutoUpdateThresholdModifications) END AS AutoUpdateThresholdProgressPercent,
                CASE WHEN nt.EstimatedAutoUpdateThresholdModifications IS NULL OR sp.modification_counter IS NULL THEN NULL
                     WHEN sp.modification_counter>=nt.EstimatedAutoUpdateThresholdModifications THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END AS AutoUpdateThresholdReached,
                nt.AutoUpdateThresholdPolicy,nt.AutoUpdateThresholdFormula,
                CONVERT(bit,CASE WHEN sp.object_id IS NULL OR nt.AutoUpdateThresholdBasisRows IS NULL OR nt.EstimatedAutoUpdateThresholdModifications IS NULL
                                      OR sp.modification_counter IS NULL OR s.no_recompute=1 OR s.is_temporary=1 THEN 0 ELSE 1 END) AS AutoUpdateThresholdApplicable,
                CASE WHEN sp.object_id IS NULL THEN ''STATISTICS_PROPERTIES_UNAVAILABLE''
                     WHEN nt.AutoUpdateThresholdBasisRows IS NULL OR nt.EstimatedAutoUpdateThresholdModifications IS NULL THEN ''THRESHOLD_BASIS_UNAVAILABLE''
                     WHEN sp.modification_counter IS NULL THEN ''MODIFICATION_COUNTER_UNAVAILABLE''
                     WHEN s.is_temporary=1 THEN ''TEMPORARY_STATISTIC_CONTEXT_REVIEW''
                     WHEN s.no_recompute=1 THEN ''NORECOMPUTE_AUTO_UPDATE_DISABLED''
                     WHEN @AutoUpdateStats=0 AND sp.modification_counter>=nt.EstimatedAutoUpdateThresholdModifications THEN ''THRESHOLD_REACHED_AUTO_UPDATE_OFF''
                     WHEN @AutoUpdateStats=0 THEN ''BELOW_THRESHOLD_AUTO_UPDATE_OFF''
                     WHEN sp.modification_counter>=nt.EstimatedAutoUpdateThresholdModifications AND @AutoUpdateStatsAsync=1 THEN ''THRESHOLD_REACHED_ASYNC''
                     WHEN sp.modification_counter>=nt.EstimatedAutoUpdateThresholdModifications THEN ''THRESHOLD_REACHED_SYNC''
                     ELSE ''BELOW_THRESHOLD'' END AS AutoUpdateThresholdState,
                @AutoUpdateStats AS AutoUpdateStatisticsOn,@AutoUpdateStatsAsync AS AutoUpdateStatisticsAsyncOn,
                @Major AS ThresholdProductMajorVersion,@Compat AS ThresholdCompatibilityLevel,@DynamicFlag AS ThresholdTraceFlag2371,
                CASE WHEN @Legacy=1 THEN ''LEGACY_CE_CONTEXT'' WHEN @Legacy=0 THEN ''MODERN_CE_CONTEXT'' ELSE ''AMBIGUOUS_CE_CONTEXT'' END AS ThresholdCEContext,
                '+CASE WHEN @HasMetadata=1 THEN N'CONVERT(decimal(19,6),sp.persisted_sample_percent)' ELSE N'CONVERT(decimal(19,6),NULL)' END+N' AS PersistedSamplePercent,
                @HasMeta AS HasPersistedSamplePercentMetadata,@Caps.value(''(/Capabilities/SupportsStatisticsMAXDOP/text())[1]'',''bit'') AS SupportsStatisticsMAXDOP,
                @SupportsPersist AS SupportsPersistSamplePercent,@Caps.value(''(/Capabilities/PreservesPersistedSampleAfterRebuild/text())[1]'',''bit'') AS PreservesPersistedSampleAfterRebuild,
                CASE WHEN @HasMeta=1 THEN ''AVAILABLE'' WHEN @HasMeta=0 AND @SupportsPersist=0 THEN ''NOT_SUPPORTED_ON_THIS_BUILD'' ELSE ''UNAVAILABLE_OR_PROBE_FAILED'' END AS PersistedSampleMetadataStatus,
                @SamplingScanBehavior AS ExpectedSamplingScanBehavior,''NOT_CAPTURED'' AS ObservedDOPStatus,''NOT_CAPTURED'' AS MemoryGrantCaptureStatus,''NOT_CAPTURED'' AS SpillCaptureStatus,
                sp.steps AS HistogramSteps,'+@HistogramSelect+N'
                @Compat AS CompatibilityLevel,@ScopedLegacy AS ScopedLegacyCE,@LegacyFlag AS LegacyTraceFlagVisible,@Legacy AS LegacyCEContext,
                @Writable AS WritablePrimary,''NOT_COLLECTED_V1'' AS QueryRegressionEvidenceStatus,''NOT_COLLECTED_V1'' AS StatisticsUsageEvidenceStatus
            FROM sys.stats s JOIN sys.tables t ON t.object_id=s.object_id JOIN sys.schemas sch ON sch.schema_id=t.schema_id
            LEFT JOIN sys.indexes i ON i.object_id=s.object_id AND i.index_id=s.stats_id
            LEFT JOIN sys.indexes b ON b.object_id=t.object_id AND b.index_id=1
            LEFT JOIN RowTotals rt ON rt.object_id=t.object_id
            LEFT JOIN sys.stats_columns sc ON sc.object_id=s.object_id AND sc.stats_id=s.stats_id AND sc.stats_column_id=1
            LEFT JOIN sys.columns c ON c.object_id=sc.object_id AND c.column_id=sc.column_id
            OUTER APPLY sys.dm_db_stats_properties(s.object_id,s.stats_id) sp
            OUTER APPLY
            (
                SELECT COALESCE(sp.unfiltered_rows,sp.rows) AS AutoUpdateThresholdBasisRows
            ) AS tb
            OUTER APPLY
            (
                SELECT tb.AutoUpdateThresholdBasisRows,
                    TRY_CONVERT(bigint,FLOOR(CASE
                        WHEN tb.AutoUpdateThresholdBasisRows IS NULL THEN NULL
                        WHEN tb.AutoUpdateThresholdBasisRows<=500 THEN CONVERT(float,500.0)
                        WHEN ((@Major>=13 OR @EngineEdition=8) AND @Compat>=130) OR @DynamicFlag=1
                            THEN CASE WHEN 500.0+(0.20*CONVERT(float,tb.AutoUpdateThresholdBasisRows))
                                           <=SQRT(1000.0*CONVERT(float,tb.AutoUpdateThresholdBasisRows))
                                      THEN 500.0+(0.20*CONVERT(float,tb.AutoUpdateThresholdBasisRows))
                                      ELSE SQRT(1000.0*CONVERT(float,tb.AutoUpdateThresholdBasisRows)) END
                        ELSE 500.0+(0.20*CONVERT(float,tb.AutoUpdateThresholdBasisRows)) END)) AS EstimatedAutoUpdateThresholdModifications,
                    CASE WHEN tb.AutoUpdateThresholdBasisRows IS NULL THEN ''UNAVAILABLE''
                         WHEN tb.AutoUpdateThresholdBasisRows<=500 THEN ''SMALL_TABLE_FIXED_500''
                         WHEN (@Major>=13 OR @EngineEdition=8) AND @Compat>=130 THEN ''DYNAMIC_COMPAT_130_PLUS''
                         WHEN @DynamicFlag=1 THEN ''DYNAMIC_GLOBAL_TF2371''
                         ELSE ''LEGACY_FIXED_20_PERCENT_PLUS_500'' END AS AutoUpdateThresholdPolicy,
                    CASE WHEN tb.AutoUpdateThresholdBasisRows IS NULL THEN ''UNAVAILABLE''
                         WHEN tb.AutoUpdateThresholdBasisRows<=500 THEN ''500''
                         WHEN ((@Major>=13 OR @EngineEdition=8) AND @Compat>=130) OR @DynamicFlag=1
                              THEN ''MIN(500 + (0.20 * n), SQRT(1000 * n))''
                         ELSE ''500 + (0.20 * n)'' END AS AutoUpdateThresholdFormula
            ) AS nt
            '+@HistogramApply+N'
            WHERE (t.is_ms_shipped=0 OR DB_ID() IN (1,3,4)) AND t.is_external=0
              AND (@OID IS NULL OR s.object_id=@OID) AND (@SID IS NULL OR s.stats_id=@SID)
              AND (NOT EXISTS(SELECT 1 FROM @Targets) OR EXISTS(SELECT 1 FROM @Targets q WHERE q.SchemaName=sch.name AND q.TableName=t.name))
              AND (@Scope=''ALL'' OR (@Scope=''INDEX_ONLY'' AND i.index_id IS NOT NULL)
                   OR (@Scope=''AUTO_ONLY'' AND i.index_id IS NULL AND s.auto_created=1)
                   OR (@Scope=''USER_ONLY'' AND i.index_id IS NULL AND s.user_created=1)
                   OR (@Scope=''NON_AUTO'' AND s.auto_created=0))
            ORDER BY sch.name,t.name,s.name FOR XML PATH(''Statistic''),ROOT(''Statistics''),TYPE);

        IF @IncludeEnv=1
        BEGIN
            SELECT @Env=(SELECT @CapturedUTC AS CapturedAtUTC,DB_NAME() AS DatabaseName,@Compat AS CompatibilityLevel,
                    @ScopedLegacy AS ScopedLegacyCE,@LegacyFlag AS LegacyTraceFlagVisible,@Writable AS WritablePrimary,
                    d.is_auto_create_stats_on AS AutoCreateStatisticsOn,d.is_auto_update_stats_on AS AutoUpdateStatisticsOn,
                    d.is_auto_update_stats_async_on AS AutoUpdateStatisticsAsyncOn,@QSState AS QueryStoreState,@Caps.query(''/Capabilities''),
                    @SamplingScanBehavior AS ExpectedSamplingScanBehavior,@ModernFlag AS ModernTraceFlagVisible,@DynamicFlag AS GlobalTraceFlag2371,
                    @Scope AS StatisticsScope,@TargetTables AS TargetTables,
                    CASE WHEN (@Major>=13 OR @EngineEdition=8) AND @Compat>=130 THEN ''DYNAMIC_COMPAT_130_PLUS''
                         WHEN @DynamicFlag=1 THEN ''DYNAMIC_GLOBAL_TF2371'' ELSE ''LEGACY_FIXED_20_PERCENT_PLUS_500'' END AS AutoUpdateThresholdContext,
                    CASE WHEN @Caps.value(''(/Capabilities/SupportsQueryStoreWaitStats/text())[1]'',''bit'')=0 THEN ''NOT_SUPPORTED_ON_THIS_BUILD''
                         WHEN @QSState NOT IN(''READ_WRITE'',''READ_ONLY'') THEN ''QUERY_STORE_NOT_ACTIVE'' ELSE ''AVAILABLE_NOT_COLLECTED'' END AS QueryStoreWaitEvidenceStatus,
                    @CEFeedbackSetting AS ScopedCEFeedback,
                    CASE WHEN @Caps.exist(''/Capabilities/SupportsCEFeedback[1]'')=1
                                   AND @Caps.value(''(/Capabilities/SupportsCEFeedback/text())[1]'',''bit'')=0
                              THEN ''NOT_SUPPORTED_ON_THIS_BUILD''
                         WHEN @CEFeedbackSetting IS NULL THEN ''SCOPED_SETTING_UNAVAILABLE_ON_THIS_POLICY''
                         WHEN @Compat<160 THEN ''COMPATIBILITY_BELOW_160'' WHEN @QSState<>''READ_WRITE'' THEN ''QUERY_STORE_NOT_READ_WRITE''
                         WHEN ISNULL(@CEFeedbackSetting,0)<>1 THEN ''SCOPED_SETTING_NOT_ENABLED'' ELSE ''DATABASE_PREREQUISITES_MET_NOT_COLLECTED'' END AS CEFeedbackEvidenceStatus,
                    (SELECT CONVERT(int,value) FROM sys.database_scoped_configurations WHERE name=N''MAXDOP'') AS DatabaseScopedMAXDOP,
                    (SELECT CONVERT(int,value_in_use) FROM sys.configurations WHERE name=N''max degree of parallelism'') AS ServerMAXDOP,
                    ''Unavailable telemetry is not zero usage; query-specific feedback and CE are not evaluated.'' AS EvidenceCoverage,
                    ''Database defaults and this maintenance session only; query-specific CE is unknown.'' AS CECoverage,
                    (SELECT OBJECT_SCHEMA_NAME(rg.object_id) AS SchemaName,OBJECT_NAME(rg.object_id) AS TableName,rg.object_id AS ObjectID,rg.index_id AS IndexID,
                            i.name AS IndexName,rg.partition_number AS PartitionNumber,SUM(CONVERT(bigint,CASE WHEN rg.state=1 THEN 1 ELSE 0 END)) AS OpenRowgroups,
                            SUM(CONVERT(bigint,CASE WHEN rg.state=2 THEN 1 ELSE 0 END)) AS ClosedRowgroups,SUM(CASE WHEN rg.state IN(1,2) THEN rg.total_rows ELSE 0 END) AS DeltaRows,
                            SUM(CASE WHEN rg.state=3 THEN rg.total_rows ELSE 0 END) AS CompressedPhysicalRows,SUM(CASE WHEN rg.state=3 THEN rg.deleted_rows ELSE 0 END) AS CompressedDeletedRows,
                            CONVERT(decimal(19,6),100.0*SUM(CASE WHEN rg.state IN(1,2) THEN CONVERT(decimal(28,6),rg.total_rows) ELSE 0 END)
                              /NULLIF(SUM(CASE WHEN rg.state IN(1,2,3) THEN CONVERT(decimal(28,6),rg.total_rows-rg.deleted_rows) ELSE 0 END),0)) AS DeltaPercentApprox,
                            ''Approximate: excludes NCCI delete-buffer rows; advisory, not an update gate.'' AS MeasurementNote
                     FROM sys.column_store_row_groups rg JOIN sys.indexes i ON i.object_id=rg.object_id AND i.index_id=rg.index_id
                     GROUP BY rg.object_id,rg.index_id,i.name,rg.partition_number FOR XML PATH(''IndexPartition''),ROOT(''ColumnstoreHealth''),TYPE)
                FROM sys.databases d WHERE d.database_id=DB_ID() FOR XML PATH(''Environment''),TYPE);
        END;';

    EXEC sys.sp_executesql @Sql,
        N'@OID int,@SID int,@IncludeEnv bit,@LegacyFlag bit,@ModernFlag bit,@DynamicFlag bit,@Caps xml,@HasMeta bit,@SupportsPersist bit,
          @HistogramCap bit,@TargetTables xml,@Scope varchar(20),@Out xml OUTPUT,@Env xml OUTPUT',
        @OID=@ObjectID,@SID=@StatsID,@IncludeEnv=@IncludeEnvironment,@LegacyFlag=@LegacyTraceFlagVisible,@ModernFlag=@ModernTraceFlagVisible,
        @DynamicFlag=@DynamicStatsTraceFlagGlobal,@Caps=@CapabilitiesXml,@HasMeta=@HasMetadata,@SupportsPersist=@SupportsPersist,
        @HistogramCap=@SupportsHistogram,@TargetTables=@TargetTablesXml,@Scope=@StatisticsScope,@Out=@SnapshotXml OUTPUT,@Env=@EnvironmentXml OUTPUT;
END;
