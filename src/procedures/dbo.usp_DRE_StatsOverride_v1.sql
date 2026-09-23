CREATE PROCEDURE dbo.usp_DRE_StatsOverride_v1
    @DatabaseName sysname, @SchemaName sysname, @TableName sysname,
    @StatName sysname, @OverrideXml xml OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @OverrideXml=NULL;
    SELECT @OverrideXml=
    (
        SELECT TOP (1) OverrideID,OverrideAction,SamplePercent,SampleRows,
            PersistenceMode,ForceUpdate,ApprovedBy,ApprovedAtUTC,
            ExpiresAtUTC,Notes,sys.fn_varbintohexstr(Revision) AS Revision
        FROM dbo.StatsGovernanceOverrides
        WHERE DatabaseName=@DatabaseName COLLATE Latin1_General_100_BIN2
          AND SchemaName=@SchemaName COLLATE Latin1_General_100_BIN2
          AND TableName=@TableName COLLATE Latin1_General_100_BIN2
          AND (StatName=@StatName COLLATE Latin1_General_100_BIN2 OR StatName IS NULL)
          AND IsEnabled=1 AND (ExpiresAtUTC IS NULL OR ExpiresAtUTC>SYSUTCDATETIME())
        ORDER BY CASE WHEN OverrideAction='EXCLUDE' THEN 0 ELSE 1 END,
                 CASE WHEN StatName IS NOT NULL THEN 0 ELSE 1 END,OverrideID
        FOR XML PATH('Override'),TYPE
    );
    IF @OverrideXml.exist('/Override[1]')=0 SET @OverrideXml=NULL;
END;
