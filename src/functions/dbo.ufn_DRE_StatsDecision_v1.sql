CREATE FUNCTION dbo.ufn_DRE_StatsDecision_v1
(
    @Facts xml,
    @Policy xml,
    @Override xml
)
RETURNS @Decision TABLE
(
    IsEligible bit NOT NULL,
    Reason varchar(80) NOT NULL,
    CollectionMethod varchar(16) NULL,
    RequestedSamplePercent decimal(19,6) NULL,
    RequestedSampleRows bigint NULL,
    SamplingSource varchar(48) NULL,
    PersistOption bit NULL,
    ModRatioPercent decimal(28,6) NULL,
    ActualSamplePercent decimal(19,6) NULL,
    LowSampleWarning bit NOT NULL,
    EffectiveLowSampleThresholdPercent decimal(19,6) NULL,
    HistogramDominantEqualityPercent decimal(19,6) NULL,
    HistogramTop3EqualityPercent decimal(19,6) NULL,
    SkewClassification varchar(12) NOT NULL,
    FullscanEligible bit NOT NULL,
    FullscanReason varchar(80) NULL,
    CanExecute bit NOT NULL,
    CapabilityReason varchar(80) NULL,
    PersistenceAdvisory varchar(80) NULL,
    GovernanceThresholdBasisRows bigint NULL,
    GovernanceEffectiveModificationThreshold bigint NULL,
    GovernanceModificationsRemaining bigint NULL,
    GovernanceThresholdProgressPercent decimal(19,6) NULL,
    GovernanceThresholdReached bit NULL,
    GovernanceVsNativeThresholdDeltaModifications bigint NULL,
    GovernanceVsNativeThresholdComparison varchar(32) NULL
)
AS
BEGIN
    /*
    FULLSCAN GOVERNANCE POLICY
    --------------------------
    Microsoft guidance states that default sampling is adequate for most workloads;
    workloads sensitive to widely varying distributions can require a larger sample
    or even a full scan, but more accurate estimates from FULLSCAN do not guarantee
    material improvement for complex plans.

    Microsoft reference:
    https://learn.microsoft.com/en-us/sql/t-sql/statements/update-statistics-transact-sql?view=sql-server-ver17

    Statistics Governance Engine policy:
      HIGH/EXTREME SKEW != AUTOMATIC FULLSCAN.

    Skew influences HOW an already-eligible statistic is sampled. Skew does not
    independently make a statistic eligible and does not authorize FULLSCAN.
    In v1.3.2 FULLSCAN is authorized only by an approved FORCE_FULLSCAN override.
    Evidence-based automatic FULLSCAN escalation is reserved for a separately
    validated future implementation.

    Units: sample-row values = rows; sample/skew values = percent.
    */
    DECLARE @Rows bigint = CASE WHEN @Facts.exist('/Statistic/StatsRows[1]')=1 THEN @Facts.value('(/Statistic/StatsRows/text())[1]','bigint') END;
    DECLARE @CurrentRows bigint = CASE WHEN @Facts.exist('/Statistic/CurrentTableRows[1]')=1 THEN @Facts.value('(/Statistic/CurrentTableRows/text())[1]','bigint') END;
    DECLARE @RowsForPolicy bigint = COALESCE(@Rows,@CurrentRows);
    DECLARE @SampleRowsObserved bigint = CASE WHEN @Facts.exist('/Statistic/RowsSampled[1]')=1 THEN @Facts.value('(/Statistic/RowsSampled/text())[1]','bigint') END;
    DECLARE @Mods bigint = CASE WHEN @Facts.exist('/Statistic/ModificationCounter[1]')=1 THEN @Facts.value('(/Statistic/ModificationCounter/text())[1]','bigint') END;
    DECLARE @Age bigint = CASE WHEN @Facts.exist('/Statistic/StatsAgeMinutes[1]')=1 THEN @Facts.value('(/Statistic/StatsAgeMinutes/text())[1]','bigint') END;
    DECLARE @Persisted decimal(19,6) = CASE WHEN @Facts.exist('/Statistic/PersistedSamplePercent[1]')=1 THEN @Facts.value('(/Statistic/PersistedSamplePercent/text())[1]','decimal(19,6)') END;
    DECLARE @IndexType int = CASE WHEN @Facts.exist('/Statistic/IndexType[1]')=1 THEN @Facts.value('(/Statistic/IndexType/text())[1]','int') END;
    DECLARE @IndexFamily varchar(20) = CASE WHEN @Facts.exist('/Statistic/IndexFamily[1]')=1 THEN @Facts.value('(/Statistic/IndexFamily/text())[1]','varchar(20)') END;
    DECLARE @Action varchar(24) = CASE WHEN @Override.exist('/Override/OverrideAction[1]')=1 THEN @Override.value('(/Override/OverrideAction/text())[1]','varchar(24)') END;
    DECLARE @OverrideSamplePercent decimal(19,6) = CASE WHEN @Override.exist('/Override/SamplePercent[1]')=1 THEN @Override.value('(/Override/SamplePercent/text())[1]','decimal(19,6)') END;
    DECLARE @OverrideSampleRows bigint = CASE WHEN @Override.exist('/Override/SampleRows[1]')=1 THEN @Override.value('(/Override/SampleRows/text())[1]','bigint') END;
    DECLARE @Force bit = ISNULL(CASE WHEN @Override.exist('/Override/ForceUpdate[1]')=1 THEN @Override.value('(/Override/ForceUpdate/text())[1]','bit') END,0);
    DECLARE @PersistMode varchar(4) = ISNULL(CASE WHEN @Override.exist('/Override/PersistenceMode[1]')=1 THEN @Override.value('(/Override/PersistenceMode/text())[1]','varchar(4)') END,'KEEP');

    DECLARE @Floor bigint = @Policy.value('(/Policy/MinRowCountFloor/text())[1]','bigint');
    DECLARE @Threshold decimal(9,4) = @Policy.value('(/Policy/UpdateThresholdPercent/text())[1]','decimal(9,4)');
    DECLARE @MinMods bigint = @Policy.value('(/Policy/MinModificationCount/text())[1]','bigint');
    DECLARE @Cooldown int = @Policy.value('(/Policy/MinUpdateIntervalMinutes/text())[1]','int');
    DECLARE @Large bigint = @Policy.value('(/Policy/LargeTableThresholdBase/text())[1]','bigint');
    DECLARE @DefaultSample decimal(9,4) = CASE WHEN @Policy.exist('/Policy/DefaultSamplePercentBase[1]')=1 THEN @Policy.value('(/Policy/DefaultSamplePercentBase/text())[1]','decimal(9,4)') END;
    DECLARE @Low decimal(19,6) = @Policy.value('(/Policy/LowSampleThresholdBase/text())[1]','decimal(19,6)');
    DECLARE @LegacyMultiplier decimal(9,4) = @Policy.value('(/Policy/LegacyCEMultiplier/text())[1]','decimal(9,4)');
    DECLARE @SkewEnabled bit = ISNULL(CASE WHEN @Policy.exist('/Policy/SkewSamplingEnabled[1]')=1 THEN @Policy.value('(/Policy/SkewSamplingEnabled/text())[1]','bit') END,0);
    DECLARE @ModerateSkew decimal(19,6) = ISNULL(CASE WHEN @Policy.exist('/Policy/ModerateSkewThresholdPercent[1]')=1 THEN @Policy.value('(/Policy/ModerateSkewThresholdPercent/text())[1]','decimal(19,6)') END,5.0);
    DECLARE @HighSkew decimal(19,6) = ISNULL(CASE WHEN @Policy.exist('/Policy/HighSkewThresholdPercent[1]')=1 THEN @Policy.value('(/Policy/HighSkewThresholdPercent/text())[1]','decimal(19,6)') END,10.0);
    DECLARE @ExtremeSkew decimal(19,6) = ISNULL(CASE WHEN @Policy.exist('/Policy/ExtremeSkewThresholdPercent[1]')=1 THEN @Policy.value('(/Policy/ExtremeSkewThresholdPercent/text())[1]','decimal(19,6)') END,25.0);
    DECLARE @HighSkewRows bigint = ISNULL(CASE WHEN @Policy.exist('/Policy/HighSkewSampleRows[1]')=1 THEN @Policy.value('(/Policy/HighSkewSampleRows/text())[1]','bigint') END,5000000);
    DECLARE @ExtremeSkewRows bigint = ISNULL(CASE WHEN @Policy.exist('/Policy/ExtremeSkewSampleRows[1]')=1 THEN @Policy.value('(/Policy/ExtremeSkewSampleRows/text())[1]','bigint') END,10000000);

    DECLARE @HistogramStatus varchar(40) = CASE WHEN @Facts.exist('/Statistic/HistogramAnalysisStatus[1]')=1 THEN @Facts.value('(/Statistic/HistogramAnalysisStatus/text())[1]','varchar(40)') END;
    DECLARE @DominantPct decimal(19,6) = CASE WHEN @Facts.exist('/Statistic/HistogramDominantEqualityPercent[1]')=1 THEN @Facts.value('(/Statistic/HistogramDominantEqualityPercent/text())[1]','decimal(19,6)') END;
    DECLARE @Top3Pct decimal(19,6) = CASE WHEN @Facts.exist('/Statistic/HistogramTop3EqualityPercent[1]')=1 THEN @Facts.value('(/Statistic/HistogramTop3EqualityPercent/text())[1]','decimal(19,6)') END;
    DECLARE @Skew varchar(12)='UNKNOWN';
    IF @HistogramStatus='AVAILABLE' AND @DominantPct IS NOT NULL
        SET @Skew=CASE WHEN @DominantPct>=@ExtremeSkew THEN 'EXTREME'
                       WHEN @DominantPct>=@HighSkew THEN 'HIGH'
                       WHEN @DominantPct>=@ModerateSkew THEN 'MODERATE'
                       ELSE 'LOW' END;

    DECLARE @MaxdopSupported bit = CASE WHEN @Facts.exist('/Statistic/SupportsStatisticsMAXDOP[1]')=1 THEN @Facts.value('(/Statistic/SupportsStatisticsMAXDOP/text())[1]','bit') END;
    DECLARE @PersistenceSupported bit = CASE WHEN @Facts.exist('/Statistic/SupportsPersistSamplePercent[1]')=1 THEN @Facts.value('(/Statistic/SupportsPersistSamplePercent/text())[1]','bit') END;
    DECLARE @HasPersistedMetadata bit = CASE WHEN @Facts.exist('/Statistic/HasPersistedSamplePercentMetadata[1]')=1 THEN @Facts.value('(/Statistic/HasPersistedSamplePercentMetadata/text())[1]','bit') END;
    DECLARE @RebuildKeepsRate bit = CASE WHEN @Facts.exist('/Statistic/PreservesPersistedSampleAfterRebuild[1]')=1 THEN @Facts.value('(/Statistic/PreservesPersistedSampleAfterRebuild/text())[1]','bit') END;

    DECLARE @CanExecute bit=0,@CapabilityReason varchar(80)=NULL,@PersistenceAdvisory varchar(80)=NULL;
    DECLARE @Method varchar(16)='AUTO',@RequestedPercent decimal(19,6)=NULL,@RequestedRows bigint=NULL,@Persist bit=NULL;
    DECLARE @Reason varchar(80),@Eligible bit=0,@SamplingSource varchar(48)='SQL_DEFAULT';
    DECLARE @ModRatio decimal(28,6),@ActualSample decimal(19,6),@LowWarning bit=0;
    DECLARE @FullscanEligible bit=0,@FullscanReason varchar(80)=NULL;
    DECLARE @NativeThreshold bigint=CASE WHEN @Facts.exist('/Statistic/EstimatedAutoUpdateThresholdModifications[1]')=1
        THEN @Facts.value('(/Statistic/EstimatedAutoUpdateThresholdModifications/text())[1]','bigint') END;
    DECLARE @GovernanceThreshold bigint=NULL,@GovernanceRemaining bigint=NULL,@GovernanceReached bit=NULL,
            @GovernanceProgress decimal(19,6)=NULL,@GovernanceDelta bigint=NULL,@GovernanceComparison varchar(32)=NULL,@GovernancePctThreshold bigint=NULL;
    IF @Rows IS NOT NULL
    BEGIN
        IF @Rows=0 SET @GovernanceThreshold=CASE WHEN @MinMods<1 THEN 1 ELSE @MinMods END;
        ELSE
        BEGIN
            SET @GovernancePctThreshold=TRY_CONVERT(bigint,CEILING(CONVERT(decimal(38,6),@Rows)*CONVERT(decimal(38,6),@Threshold)/100.0));
            IF @GovernancePctThreshold IS NOT NULL
                SET @GovernanceThreshold=CASE WHEN @GovernancePctThreshold>@MinMods THEN @GovernancePctThreshold ELSE @MinMods END;
        END;
    END;
    IF @GovernanceThreshold IS NOT NULL AND @Mods IS NOT NULL
    BEGIN
        SET @GovernanceRemaining=CASE WHEN @Mods>=@GovernanceThreshold THEN 0 ELSE @GovernanceThreshold-@Mods END;
        SET @GovernanceProgress=CASE WHEN @GovernanceThreshold=0 THEN NULL
            ELSE CONVERT(decimal(19,6),CONVERT(decimal(38,6),@Mods)*100.0/CONVERT(decimal(38,6),@GovernanceThreshold)) END;
        SET @GovernanceReached=CASE WHEN @Mods>=@GovernanceThreshold THEN 1 ELSE 0 END;
    END;
    IF @GovernanceThreshold IS NOT NULL AND @NativeThreshold IS NOT NULL
    BEGIN
        SET @GovernanceDelta=TRY_CONVERT(bigint,CONVERT(decimal(38,0),@GovernanceThreshold)-CONVERT(decimal(38,0),@NativeThreshold));
        SET @GovernanceComparison=CASE WHEN @GovernanceThreshold<@NativeThreshold THEN 'GOVERNANCE_EARLIER'
                                       WHEN @GovernanceThreshold>@NativeThreshold THEN 'GOVERNANCE_LATER'
                                       ELSE 'SAME_THRESHOLD' END;
    END;

    IF @Facts.value('(/Statistic/LegacyCEContext/text())[1]','bit')=1 SET @Low=@Low*@LegacyMultiplier;
    IF @Low>100 SET @Low=100;
    IF @Rows>0
    BEGIN
        SET @ModRatio=CONVERT(decimal(28,6),CONVERT(decimal(28,6),@Mods)/NULLIF(@Rows,0)*100.0);
        SET @ActualSample=CONVERT(decimal(19,6),CONVERT(decimal(28,6),@SampleRowsObserved)/NULLIF(@Rows,0)*100.0);
    END;
    IF @ActualSample<@Low SET @LowWarning=1;

    -- Safety restrictions precede manual overrides. Non-rowstore associated
    -- statistics remain visible in INDEX_ONLY reports but are deferred explicitly.
    IF ISNULL(@Facts.value('(/Statistic/WritablePrimary/text())[1]','bit'),0)<>1
        SET @Reason='DATABASE_NOT_WRITABLE_PRIMARY';
    ELSE IF @Facts.value('(/Statistic/IsMemoryOptimized/text())[1]','bit')=1
        SET @Reason='MEMORY_OPTIMIZED_MANUAL_REVIEW_V1';
    ELSE IF @Facts.value('(/Statistic/IsTemporary/text())[1]','bit')=1
        SET @Reason='TEMPORARY_STATISTIC_NOT_SUPPORTED';
    ELSE IF @Facts.value('(/Statistic/BaseIndexDisabled/text())[1]','bit')=1
         OR @Facts.value('(/Statistic/IndexDisabled/text())[1]','bit')=1
         OR @Facts.value('(/Statistic/IndexHypothetical/text())[1]','bit')=1
        SET @Reason='DISABLED_OR_HYPOTHETICAL_INDEX';
    ELSE IF @IndexType IN (5,6) SET @Reason='COLUMNSTORE_INDEX_STATISTIC_DEFERRED';
    ELSE IF @IndexType=3 SET @Reason='XML_INDEX_STATISTIC_DEFERRED';
    ELSE IF @IndexType=4 SET @Reason='SPATIAL_INDEX_STATISTIC_DEFERRED';
    ELSE IF @IndexType=7 SET @Reason='HASH_INDEX_STATISTIC_DEFERRED';
    ELSE IF @IndexType=9 SET @Reason='JSON_INDEX_STATISTIC_DEFERRED';
    ELSE IF @IndexType IS NOT NULL AND @IndexType NOT IN (1,2)
        SET @Reason='UNKNOWN_INDEX_FAMILY_DEFERRED';
    ELSE IF @Facts.value('(/Statistic/IsIncremental/text())[1]','bit')=1
        SET @Reason='INCREMENTAL_PARTITION_EXECUTOR_DEFERRED_V1';
    ELSE IF @Action='EXCLUDE'
        SET @Reason='EXPLICIT_EXCLUSION';
    ELSE IF ISNULL(@Facts.value('(/Statistic/StatsPropertiesAvailable/text())[1]','bit'),0)<>1
        SET @Reason='STATISTICS_PROPERTIES_UNAVAILABLE';
    ELSE IF @CurrentRows IS NULL SET @Reason='CURRENT_ROWCOUNT_UNAVAILABLE';
    ELSE IF @CurrentRows=0 SET @Reason='EMPTY_TABLE';
    ELSE IF @CurrentRows<@Floor AND @Action IS NULL SET @Reason='BELOW_ROWCOUNT_FLOOR';
    ELSE IF @Age IS NOT NULL AND @Age<@Cooldown SET @Reason='UPDATE_COOLDOWN';
    ELSE IF @Force=1 BEGIN SET @Eligible=1; SET @Reason='APPROVED_FORCE_REFRESH'; END
    ELSE IF @Facts.exist('/Statistic/LastUpdatedLocal[1]')=0 AND @Facts.value('(/Statistic/HasFilter/text())[1]','bit')=1
        SET @Reason='FILTERED_EMPTY_OR_UNINITIALIZED_REVIEW';
    ELSE IF @Facts.exist('/Statistic/LastUpdatedLocal[1]')=0 BEGIN SET @Eligible=1; SET @Reason='MISSING_STATISTICS_BLOB'; END
    ELSE IF @Mods IS NULL SET @Reason='MODIFICATION_COUNTER_UNAVAILABLE';
    ELSE IF @Mods<@MinMods OR @Mods=0 SET @Reason='BELOW_MIN_MODIFICATIONS';
    ELSE IF @Rows=0 BEGIN SET @Eligible=1; SET @Reason='ZERO_BASELINE_WITH_MODIFICATIONS'; END
    ELSE IF @ModRatio>=@Threshold BEGIN SET @Eligible=1; SET @Reason='MODIFICATION_THRESHOLD'; END
    ELSE SET @Reason='BELOW_MODIFICATION_THRESHOLD';

    IF @Eligible=1
    BEGIN
        IF @Action='FORCE_FULLSCAN'
        BEGIN
            SET @Method='FULLSCAN'; SET @RequestedPercent=100.0; SET @SamplingSource='APPROVED_OVERRIDE';
            SET @FullscanEligible=1; SET @FullscanReason='APPROVED_FORCE_FULLSCAN_OVERRIDE';
        END
        ELSE IF @Action='FORCE_SAMPLE_PERCENT'
        BEGIN
            SET @Method='SAMPLE_PERCENT'; SET @RequestedPercent=@OverrideSamplePercent; SET @SamplingSource='APPROVED_OVERRIDE';
        END
        ELSE IF @Action='FORCE_SAMPLE_ROWS'
        BEGIN
            IF @OverrideSampleRows IS NULL OR @OverrideSampleRows<=0
            BEGIN SET @Eligible=0; SET @Reason='INVALID_SAMPLE_ROWS_OVERRIDE'; END
            ELSE IF @PersistMode='ON'
            BEGIN SET @Eligible=0; SET @Reason='SAMPLE_ROWS_CANNOT_PERSIST_ROW_COUNT'; END
            ELSE IF ISNULL(@Persisted,0)>0 AND @PersistMode='KEEP'
            BEGIN SET @Eligible=0; SET @Reason='ROW_SAMPLE_CONFLICTS_WITH_PERSISTED_PERCENT'; END
            ELSE
            BEGIN
                SET @Method='SAMPLE_ROWS';
                SET @RequestedRows=CASE WHEN @CurrentRows IS NOT NULL AND @OverrideSampleRows>@CurrentRows THEN @CurrentRows ELSE @OverrideSampleRows END;
                SET @SamplingSource=CASE WHEN @CurrentRows IS NOT NULL AND @OverrideSampleRows>@CurrentRows THEN 'APPROVED_OVERRIDE_CAPPED_TO_ROWS' ELSE 'APPROVED_OVERRIDE' END;
                IF @PersistMode='OFF' SET @Persist=0;
            END;
        END
        ELSE IF ISNULL(@Persisted,0)>0 AND @PersistenceSupported=1 AND @HasPersistedMetadata=1
        BEGIN
            SET @Method='SAMPLE_PERCENT'; SET @RequestedPercent=@Persisted;
            SET @PersistMode='ON'; SET @Persist=1; SET @SamplingSource='EXISTING_PERSISTED_RATE';
        END
        ELSE IF @SkewEnabled=1 AND @RowsForPolicy>=@Large AND @Skew IN ('HIGH','EXTREME')
        BEGIN
            -- Skew can raise the sampling budget, but never promotes to FULLSCAN.
            SET @Method='SAMPLE_ROWS';
            SET @RequestedRows=CASE WHEN @Skew='EXTREME' THEN @ExtremeSkewRows ELSE @HighSkewRows END;
            IF @CurrentRows IS NOT NULL AND @RequestedRows>@CurrentRows SET @RequestedRows=@CurrentRows;
            SET @SamplingSource=CASE WHEN @Skew='EXTREME' THEN 'EXTREME_SKEW_SAMPLE_ROWS' ELSE 'HIGH_SKEW_SAMPLE_ROWS' END;
        END
        ELSE IF @Action IS NULL AND @DefaultSample IS NOT NULL AND @RowsForPolicy>=@Large
        BEGIN
            SET @Method='SAMPLE_PERCENT'; SET @RequestedPercent=@DefaultSample; SET @SamplingSource='REQUESTED_LARGE_TABLE_SAMPLE';
        END;

        IF @Eligible=1 AND @Method IN ('FULLSCAN','SAMPLE_PERCENT') AND @Persist IS NULL
        BEGIN
            IF @PersistMode='ON' SET @Persist=1;
            ELSE IF @PersistMode='OFF' SET @Persist=0;
            ELSE IF ISNULL(@Persisted,0)=0 AND @PersistenceSupported=1 SET @Persist=0;
            ELSE IF @PersistenceSupported=0 SET @Persist=NULL;
            ELSE IF @RequestedPercent IS NOT NULL AND ABS(@Persisted-@RequestedPercent)<=0.0001 SET @Persist=1;
            ELSE BEGIN SET @Eligible=0; SET @Reason='PERSISTENCE_CONFLICT_REQUIRES_EXPLICIT_CHOICE'; END;
        END;
    END;

    -- Capability checks are only execution gates; they do not alter policy eligibility.
    IF @Eligible=1
    BEGIN
        IF @MaxdopSupported IS NULL SET @CapabilityReason='STATISTICS_MAXDOP_CAPABILITY_UNKNOWN';
        ELSE IF @MaxdopSupported=0 SET @CapabilityReason='STATISTICS_MAXDOP_NOT_SUPPORTED_ON_THIS_BUILD';
        ELSE IF @Persist IS NOT NULL AND @PersistenceSupported IS NULL SET @CapabilityReason='PERSIST_SAMPLE_CAPABILITY_UNKNOWN';
        ELSE IF @Persist IS NOT NULL AND @PersistenceSupported=0 SET @CapabilityReason='PERSIST_SAMPLE_OPTION_NOT_SUPPORTED_ON_THIS_BUILD';
        ELSE IF @Persist IS NOT NULL AND @PersistenceSupported=1 AND ISNULL(@HasPersistedMetadata,0)<>1 SET @CapabilityReason='PERSISTED_SAMPLE_METADATA_UNAVAILABLE';
        ELSE IF @Method='SAMPLE_PERCENT' AND @SamplingSource='EXISTING_PERSISTED_RATE' AND (ISNULL(@PersistenceSupported,0)<>1 OR ISNULL(@HasPersistedMetadata,0)<>1)
            SET @CapabilityReason='EXISTING_PERSISTED_RATE_CANNOT_BE_VALIDATED';
    END;
    SET @CanExecute=CASE WHEN @Eligible=1 AND @CapabilityReason IS NULL THEN 1 ELSE 0 END;

    IF @PersistenceSupported=1 AND @RebuildKeepsRate=0 SET @PersistenceAdvisory='INDEX_REBUILD_CAN_RESET_PERSISTED_SAMPLE';
    ELSE IF @PersistenceSupported=1 AND @RebuildKeepsRate IS NULL SET @PersistenceAdvisory='REBUILD_PERSISTENCE_BEHAVIOR_UNKNOWN';
    ELSE IF @PersistenceSupported=0 SET @PersistenceAdvisory='PERSISTED_SAMPLING_NOT_SUPPORTED_ON_THIS_BUILD';

    INSERT @Decision
    VALUES(@Eligible,@Reason,CASE WHEN @Eligible=1 THEN @Method END,
           CASE WHEN @Eligible=1 THEN @RequestedPercent END,
           CASE WHEN @Eligible=1 THEN @RequestedRows END,
           CASE WHEN @Eligible=1 THEN @SamplingSource END,
           CASE WHEN @Eligible=1 THEN @Persist END,
           @ModRatio,@ActualSample,@LowWarning,@Low,@DominantPct,@Top3Pct,@Skew,
           @FullscanEligible,@FullscanReason,@CanExecute,@CapabilityReason,@PersistenceAdvisory,
           @Rows,@GovernanceThreshold,@GovernanceRemaining,@GovernanceProgress,@GovernanceReached,@GovernanceDelta,@GovernanceComparison);
    RETURN;
END;
