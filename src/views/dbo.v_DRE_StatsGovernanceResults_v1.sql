CREATE VIEW dbo.v_DRE_StatsGovernanceResults_v1
AS
SELECT t.TelemetryID,t.RunID,r.Mode,t.DatabaseName,t.SchemaName,t.TableName,t.StatName,
    t.InitialSnapshotXml.value('(/Statistic/StatisticType/text())[1]','varchar(20)') AS StatisticType,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/IndexName[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/IndexName/text())[1]','nvarchar(128)') END AS IndexName,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/IndexType[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/IndexType/text())[1]','tinyint') END AS IndexType,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/IndexTypeDescription[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/IndexTypeDescription/text())[1]','nvarchar(60)') END AS IndexTypeDescription,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/IndexFamily[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/IndexFamily/text())[1]','varchar(20)') END AS IndexFamily,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/StatisticsContext[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/StatisticsContext/text())[1]','varchar(50)') END AS StatisticsContext,
    t.InitialSnapshotXml.value('(/Statistic/BaseStorage/text())[1]','varchar(30)') AS BaseStorage,
    t.InitialSnapshotXml.value('(/Statistic/HasColumnstore/text())[1]','bit') AS HasColumnstore,
    t.InitialSnapshotXml.value('(/Statistic/IsIncremental/text())[1]','bit') AS IsIncremental,
    t.InitialSnapshotXml.value('(/Statistic/HasFilter/text())[1]','bit') AS HasFilter,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/CurrentTableRows[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/CurrentTableRows/text())[1]','bigint') END AS CurrentTableRows,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/StatsRows[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/StatsRows/text())[1]','bigint') END AS StatsRowsAtLastUpdate,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/UnfilteredRowsAtLastUpdate[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/UnfilteredRowsAtLastUpdate/text())[1]','bigint') END AS UnfilteredRowsAtLastUpdate,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/RowCountDeltaSinceStatsUpdate[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/RowCountDeltaSinceStatsUpdate/text())[1]','bigint') END AS RowCountDeltaSinceStatsUpdate,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/RowsSampled[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/RowsSampled/text())[1]','bigint') END AS RowsSampledBefore,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ModificationCounter[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ModificationCounter/text())[1]','bigint') END AS ModificationCounter,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/NoRecompute[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/NoRecompute/text())[1]','bit') END AS NoRecompute,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdBasisRows[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdBasisRows/text())[1]','bigint') END AS AutoUpdateThresholdBasisRows,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/EstimatedAutoUpdateThresholdModifications[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/EstimatedAutoUpdateThresholdModifications/text())[1]','bigint') END AS EstimatedAutoUpdateThresholdModifications,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/EstimatedNextAutoUpdateAtModificationCounter[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/EstimatedNextAutoUpdateAtModificationCounter/text())[1]','bigint') END AS EstimatedNextAutoUpdateAtModificationCounter,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdIsEstimate[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdIsEstimate/text())[1]','bit') END AS AutoUpdateThresholdIsEstimate,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/EstimatedModificationsRemainingToAutoUpdate[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/EstimatedModificationsRemainingToAutoUpdate/text())[1]','bigint') END AS EstimatedModificationsRemainingToAutoUpdate,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdProgressPercent[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdProgressPercent/text())[1]','decimal(19,6)') END AS AutoUpdateThresholdProgressPercent,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdReached[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdReached/text())[1]','bit') END AS AutoUpdateThresholdReached,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdPolicy[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdPolicy/text())[1]','varchar(48)') END AS AutoUpdateThresholdPolicy,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdFormula[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdFormula/text())[1]','varchar(100)') END AS AutoUpdateThresholdFormula,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdApplicable[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdApplicable/text())[1]','bit') END AS AutoUpdateThresholdApplicable,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdState[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdState/text())[1]','varchar(64)') END AS AutoUpdateThresholdState,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateStatisticsOn[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateStatisticsOn/text())[1]','bit') END AS AutoUpdateStatisticsOn,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateStatisticsAsyncOn[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateStatisticsAsyncOn/text())[1]','bit') END AS AutoUpdateStatisticsAsyncOn,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ThresholdProductMajorVersion[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ThresholdProductMajorVersion/text())[1]','int') END AS ThresholdProductMajorVersion,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ThresholdCompatibilityLevel[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ThresholdCompatibilityLevel/text())[1]','int') END AS ThresholdCompatibilityLevel,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ThresholdTraceFlag2371[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ThresholdTraceFlag2371/text())[1]','bit') END AS ThresholdTraceFlag2371,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ThresholdCEContext[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ThresholdCEContext/text())[1]','varchar(32)') END AS ThresholdCEContext,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceThresholdBasisRows[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceThresholdBasisRows/text())[1]','bigint') END AS GovernanceThresholdBasisRows,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceEffectiveModificationThreshold[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceEffectiveModificationThreshold/text())[1]','bigint') END AS GovernanceEffectiveModificationThreshold,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceModificationsRemaining[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceModificationsRemaining/text())[1]','bigint') END AS GovernanceModificationsRemaining,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceThresholdProgressPercent[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceThresholdProgressPercent/text())[1]','decimal(19,6)') END AS GovernanceThresholdProgressPercent,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceThresholdReached[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceThresholdReached/text())[1]','bit') END AS GovernanceThresholdReached,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceVsNativeThresholdDeltaModifications[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceVsNativeThresholdDeltaModifications/text())[1]','bigint') END AS GovernanceVsNativeThresholdDeltaModifications,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceVsNativeThresholdComparison[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceVsNativeThresholdComparison/text())[1]','varchar(32)') END AS GovernanceVsNativeThresholdComparison,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/LastUpdatedLocal[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/LastUpdatedLocal/text())[1]','datetime2(7)') END AS LastUpdatedLocalBefore,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/ModRatioPercent[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/ModRatioPercent/text())[1]','decimal(28,6)') END AS ModRatioPercent,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/ActualSamplePercent[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/ActualSamplePercent/text())[1]','decimal(19,6)') END AS ActualSamplePercentBefore,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/PersistedSamplePercent[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/PersistedSamplePercent/text())[1]','decimal(19,6)') END AS PersistedSamplePercentBefore,
    t.InitialDecisionXml.value('(/Decision/LowSampleWarning/text())[1]','bit') AS LowSampleWarning,
    t.InitialDecisionXml.value('(/Decision/EffectiveLowSampleThresholdPercent/text())[1]','decimal(19,6)') AS EffectiveLowSampleThresholdPercent,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/LegacyCEContext[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/LegacyCEContext/text())[1]','bit') END AS LegacyCEContext,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/HistogramAnalysisStatus[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/HistogramAnalysisStatus/text())[1]','varchar(40)') END AS HistogramAnalysisStatus,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/HistogramDominantEqualityPercent[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/HistogramDominantEqualityPercent/text())[1]','decimal(19,6)') END AS HistogramDominantEqualityPercent,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/HistogramTop3EqualityPercent[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/HistogramTop3EqualityPercent/text())[1]','decimal(19,6)') END AS HistogramTop3EqualityPercent,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/SkewClassification[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/SkewClassification/text())[1]','varchar(12)') END AS SkewClassification,
    t.InitialDecisionXml.value('(/Decision/IsEligible/text())[1]','bit') AS InitiallyEligible,
    t.InitialDecisionXml.value('(/Decision/Reason/text())[1]','varchar(80)') AS InitialReason,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/CollectionMethod[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/CollectionMethod/text())[1]','varchar(16)') END AS ProposedMethod,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/SamplingSource[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/SamplingSource/text())[1]','varchar(48)') END AS SamplingSource,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/RequestedSamplePercent[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/RequestedSamplePercent/text())[1]','decimal(19,6)') END AS RequestedSamplePercent,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/RequestedSampleRows[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/RequestedSampleRows/text())[1]','bigint') END AS RequestedSampleRows,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/PersistOption[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/PersistOption/text())[1]','bit') END AS ProposedPersistOption,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/FullscanEligible[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/FullscanEligible/text())[1]','bit') END AS FullscanEligible,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/FullscanReason[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/FullscanReason/text())[1]','varchar(80)') END AS FullscanReason,
    CASE WHEN r.ParametersXml.exist('/Policy/StatisticsScope[1]')=1
         THEN r.ParametersXml.value('(/Policy/StatisticsScope/text())[1]','varchar(20)') ELSE 'ALL' END AS StatisticsScope,
    CASE WHEN r.ParametersXml.exist('/Policy/TargetTablesXml/TableTargets/Table[1]')=1 THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END AS IsTargetedTableRun,
    r.RequestedMAXDOP,t.OverrideID,t.RecommendedCommand,t.ExecutedCommand,t.CommandLogID,
    t.ExecutionStatus,t.ExecutionReason,t.CommandElapsedMilliseconds,
    CASE WHEN t.AfterSnapshotXml.exist('/Statistic/StatsRows[1]')=1
         THEN t.AfterSnapshotXml.value('(/Statistic/StatsRows/text())[1]','bigint') END AS StatsRowsAfter,
    CASE WHEN t.AfterSnapshotXml.exist('/Statistic/RowsSampled[1]')=1
         THEN t.AfterSnapshotXml.value('(/Statistic/RowsSampled/text())[1]','bigint') END AS RowsSampledAfter,
    CASE WHEN t.AfterSnapshotXml.exist('/Statistic/LastUpdatedLocal[1]')=1
         THEN t.AfterSnapshotXml.value('(/Statistic/LastUpdatedLocal/text())[1]','datetime2(7)') END AS LastUpdatedLocalAfter,
    CASE WHEN t.AfterSnapshotXml.exist('/Statistic/PersistedSamplePercent[1]')=1
         THEN t.AfterSnapshotXml.value('(/Statistic/PersistedSamplePercent/text())[1]','decimal(19,6)') END AS PersistedSamplePercentAfter,
    t.PostcheckStatus,t.ErrorNumber,t.ErrorMessage,t.PostcheckErrorNumber,t.PostcheckErrorMessage,
    r.EngineVersion,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/CanExecute[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/CanExecute/text())[1]','bit') END AS InitiallyExecutable,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/CapabilityReason[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/CapabilityReason/text())[1]','varchar(80)') END AS CapabilityReason,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/PersistenceAdvisory[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/PersistenceAdvisory/text())[1]','varchar(80)') END AS PersistenceAdvisory,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/PersistedSampleMetadataStatus[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/PersistedSampleMetadataStatus/text())[1]','varchar(40)') END AS PersistedSampleMetadataStatus,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ExpectedSamplingScanBehavior[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ExpectedSamplingScanBehavior/text())[1]','varchar(100)') END AS ExpectedSamplingScanBehavior
FROM dbo.StatsGovernanceTelemetry AS t
JOIN dbo.StatsGovernanceRuns AS r ON r.RunID=t.RunID;
