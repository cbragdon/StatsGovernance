SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Policy xml=N'<Policy><MinRowCountFloor>0</MinRowCountFloor><UpdateThresholdPercent>10</UpdateThresholdPercent><MinModificationCount>500</MinModificationCount><MinUpdateIntervalMinutes>60</MinUpdateIntervalMinutes><LargeTableThresholdBase>20000000</LargeTableThresholdBase><LowSampleThresholdBase>2</LowSampleThresholdBase><LegacyCEMultiplier>2</LegacyCEMultiplier><SkewSamplingEnabled>0</SkewSamplingEnabled></Policy>';
DECLARE @Facts xml=N'<Statistic><StatsRows>400000</StatsRows><CurrentTableRows>400000</CurrentTableRows><RowsSampled>5000</RowsSampled><ModificationCounter>50000</ModificationCounter><StatsAgeMinutes>120</StatsAgeMinutes><IndexType>2</IndexType><IndexFamily>ROWSTORE</IndexFamily><LegacyCEContext>0</LegacyCEContext><WritablePrimary>1</WritablePrimary><IsMemoryOptimized>0</IsMemoryOptimized><IsTemporary>0</IsTemporary><BaseIndexDisabled>0</BaseIndexDisabled><IndexDisabled>0</IndexDisabled><IndexHypothetical>0</IndexHypothetical><IsIncremental>0</IsIncremental><StatsPropertiesAvailable>1</StatsPropertiesAvailable><HasFilter>0</HasFilter><LastUpdatedLocal>2026-09-20T00:00:00</LastUpdatedLocal><SupportsStatisticsMAXDOP>1</SupportsStatisticsMAXDOP><SupportsPersistSamplePercent>1</SupportsPersistSamplePercent><HasPersistedSamplePercentMetadata>1</HasPersistedSamplePercentMetadata><PreservesPersistedSampleAfterRebuild>1</PreservesPersistedSampleAfterRebuild><HistogramAnalysisStatus>AVAILABLE</HistogramAnalysisStatus><HistogramDominantEqualityPercent>30</HistogramDominantEqualityPercent><EstimatedAutoUpdateThresholdModifications>20000</EstimatedAutoUpdateThresholdModifications></Statistic>';

SELECT N'SKEW_WITHOUT_FULLSCAN' AS Scenario, *
FROM dbo.ufn_DRE_StatsDecision_v1(@Facts,@Policy,NULL);
IF NOT EXISTS
(
    SELECT 1 FROM dbo.ufn_DRE_StatsDecision_v1(@Facts,@Policy,NULL)
    WHERE IsEligible=1 AND CanExecute=1 AND CollectionMethod='AUTO'
      AND FullscanEligible=0 AND SkewClassification='EXTREME'
      AND GovernanceEffectiveModificationThreshold=40000
      AND GovernanceThresholdProgressPercent=125
      AND GovernanceVsNativeThresholdComparison='GOVERNANCE_LATER'
)
    THROW 51310,'Skew/threshold baseline decision mismatch.',1;

DECLARE @RowsOverride xml=N'<Override><OverrideAction>FORCE_SAMPLE_ROWS</OverrideAction><SampleRows>25000</SampleRows><PersistenceMode>OFF</PersistenceMode><ForceUpdate>1</ForceUpdate></Override>';
SELECT N'FORCE_SAMPLE_ROWS' AS Scenario, *
FROM dbo.ufn_DRE_StatsDecision_v1(@Facts,@Policy,@RowsOverride);
IF NOT EXISTS
(
    SELECT 1 FROM dbo.ufn_DRE_StatsDecision_v1(@Facts,@Policy,@RowsOverride)
    WHERE IsEligible=1 AND CanExecute=1 AND CollectionMethod='SAMPLE_ROWS'
      AND RequestedSampleRows=25000 AND RequestedSamplePercent IS NULL
      AND PersistOption=0 AND FullscanEligible=0
)
    THROW 51311,'Approved SAMPLE ROWS decision mismatch.',1;

DECLARE @FullscanOverride xml=N'<Override><OverrideAction>FORCE_FULLSCAN</OverrideAction><PersistenceMode>OFF</PersistenceMode><ForceUpdate>1</ForceUpdate></Override>';
SELECT N'FORCE_FULLSCAN' AS Scenario, *
FROM dbo.ufn_DRE_StatsDecision_v1(@Facts,@Policy,@FullscanOverride);
IF NOT EXISTS
(
    SELECT 1 FROM dbo.ufn_DRE_StatsDecision_v1(@Facts,@Policy,@FullscanOverride)
    WHERE IsEligible=1 AND CanExecute=1 AND CollectionMethod='FULLSCAN'
      AND FullscanEligible=1 AND PersistOption=0
)
    THROW 51312,'Approved FULLSCAN decision mismatch.',1;

DECLARE @NoMaxdop xml=REPLACE(CONVERT(nvarchar(max),@Facts),N'<SupportsStatisticsMAXDOP>1</SupportsStatisticsMAXDOP>',N'<SupportsStatisticsMAXDOP>0</SupportsStatisticsMAXDOP>');
SELECT N'UNSUPPORTED_MAXDOP' AS Scenario, *
FROM dbo.ufn_DRE_StatsDecision_v1(@NoMaxdop,@Policy,NULL);
IF NOT EXISTS
(
    SELECT 1 FROM dbo.ufn_DRE_StatsDecision_v1(@NoMaxdop,@Policy,NULL)
    WHERE IsEligible=1 AND CanExecute=0
      AND CapabilityReason='STATISTICS_MAXDOP_NOT_SUPPORTED_ON_THIS_BUILD'
)
    THROW 51313,'Unsupported MAXDOP did not block execution.',1;

SELECT N'DECISION_MATRIX_PASS' AS Status;
