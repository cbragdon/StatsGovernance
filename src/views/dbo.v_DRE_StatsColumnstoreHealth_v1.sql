CREATE VIEW dbo.v_DRE_StatsColumnstoreHealth_v1
AS
SELECT d.RunID,d.DatabaseName,
       n.p.value('(SchemaName/text())[1]','nvarchar(128)') AS SchemaName,
       n.p.value('(TableName/text())[1]','nvarchar(128)') AS TableName,
       n.p.value('(IndexName/text())[1]','nvarchar(128)') AS IndexName,
       n.p.value('(IndexID/text())[1]','int') AS IndexID,
       n.p.value('(PartitionNumber/text())[1]','int') AS PartitionNumber,
       n.p.value('(OpenRowgroups/text())[1]','bigint') AS OpenRowgroups,
       n.p.value('(ClosedRowgroups/text())[1]','bigint') AS ClosedRowgroups,
       n.p.value('(DeltaRows/text())[1]','bigint') AS DeltaRows,
       n.p.value('(CompressedPhysicalRows/text())[1]','bigint') AS CompressedPhysicalRows,
       n.p.value('(CompressedDeletedRows/text())[1]','bigint') AS CompressedDeletedRows,
       CASE WHEN n.p.exist('DeltaPercentApprox[1]')=1
            THEN n.p.value('(DeltaPercentApprox/text())[1]','decimal(19,6)') END AS DeltaPercentApprox,
       n.p.value('(MeasurementNote/text())[1]','nvarchar(200)') AS MeasurementNote
FROM dbo.StatsGovernanceRunDatabases AS d
CROSS APPLY d.EnvironmentXml.nodes('/Environment/ColumnstoreHealth/IndexPartition') AS n(p);
