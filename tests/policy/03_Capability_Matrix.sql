USE [DBAdmin];
SET NOCOUNT ON;

DECLARE @Cases TABLE
(
    CaseName varchar(40) NOT NULL,
    ProductVersion nvarchar(128) NOT NULL,
    EngineEdition int NOT NULL,
    CreateAlter bit NOT NULL,
    StatsMAXDOP bit NOT NULL,
    PersistSample bit NOT NULL,
    RebuildKeepsSample bit NOT NULL,
    Histogram bit NOT NULL
);
INSERT @Cases VALUES
('SQL2016_RTM','13.0.1601.5',3,0,0,0,0,0),
('SQL2016_SP1_CU2','13.0.4422.0',3,1,0,0,0,1),
('SQL2016_SP1_CU3','13.0.4435.0',3,1,0,0,0,1),
('SQL2016_SP1_CU4','13.0.4446.0',3,1,0,1,0,1),
('SQL2016_SP2','13.0.5026.0',3,1,1,1,0,1),
('SQL2016_SP2_CU17','13.0.5888.11',3,1,1,1,1,1),
('SQL2017_RTM','14.0.1000.169',3,1,0,0,0,1),
('SQL2017_CU1','14.0.3006.16',3,1,0,1,0,1),
('SQL2017_CU2','14.0.3008.27',3,1,0,1,0,1),
('SQL2017_CU3','14.0.3015.40',3,1,1,1,0,1),
('SQL2017_CU26','14.0.3411.3',3,1,1,1,1,1),
('SQL2019_RTM','15.0.2000.5',3,1,1,1,0,1),
('SQL2019_CU10','15.0.4123.1',3,1,1,1,1,1),
('SQL2022_RTM','16.0.1000.6',3,1,1,1,1,1),
('SQL2025_CU8','17.0.4085.5',3,1,1,1,1,1),
('AZURE_MI_REPORTED_12','12.0.2000.8',8,1,1,1,1,1);

SELECT c.CaseName,c.ProductVersion,c.EngineEdition,
       f.SupportedEngine,f.SupportsCreateOrAlter,
       f.SupportsStatisticsMAXDOP,f.SupportsPersistSamplePercent,
       f.PreservesPersistedSampleAfterRebuild,f.SupportsStatsHistogramDMF
FROM @Cases AS c
CROSS APPLY dbo.ufn_DRE_StatsCapabilities_v1(c.ProductVersion,c.EngineEdition) AS f
ORDER BY c.CaseName;

IF EXISTS
(
    SELECT 1 FROM @Cases AS c
    CROSS APPLY dbo.ufn_DRE_StatsCapabilities_v1(c.ProductVersion,c.EngineEdition) AS f
    WHERE f.SupportedEngine<>1
       OR f.SupportsCreateOrAlter<>c.CreateAlter
       OR f.SupportsStatisticsMAXDOP<>c.StatsMAXDOP
       OR f.SupportsPersistSamplePercent<>c.PersistSample
       OR f.PreservesPersistedSampleAfterRebuild<>c.RebuildKeepsSample
       OR f.SupportsStatsHistogramDMF<>c.Histogram
)
    THROW 51320,'Capability matrix differs from expected version/build gates.',1;

IF NOT EXISTS
(
    SELECT 1 FROM dbo.ufn_DRE_StatsCapabilities_v1(N'12.0.2000.8',8)
    WHERE SupportedEngine=1 AND SupportsCEFeedback IS NULL
)
    THROW 51321,'Managed Instance CE feedback must remain policy-dependent/unknown.',1;

SELECT N'CAPABILITY_MATRIX_PASS' AS Status;
