CREATE PROCEDURE dbo.usp_DRE_StatsCapabilities_v1
    @CapabilitiesXml xml=NULL OUTPUT, @EmitResult bit=1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Version nvarchar(128)=CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion')),
            @Edition int=CONVERT(int,SERVERPROPERTY('EngineEdition')),
            @HasMetadata bit=NULL,@ProbeStatus varchar(40)='NOT_ATTEMPTED',
            @ProbeError int=NULL,@ProbeMessage nvarchar(4000)=NULL;
    DECLARE @Description TABLE(ColumnName sysname COLLATE DATABASE_DEFAULT NULL,ErrorNumber int NULL,ErrorMessage nvarchar(4000) COLLATE DATABASE_DEFAULT NULL);
    BEGIN TRY
        INSERT @Description(ColumnName,ErrorNumber,ErrorMessage)
            SELECT name,error_number,error_message
            FROM sys.dm_exec_describe_first_result_set
                (N'SELECT * FROM sys.dm_db_stats_properties(NULL,NULL);',NULL,0);
        IF EXISTS(SELECT 1 FROM @Description WHERE ErrorNumber IS NOT NULL)
        BEGIN
            SELECT TOP(1) @ProbeError=ErrorNumber,@ProbeMessage=ErrorMessage
            FROM @Description WHERE ErrorNumber IS NOT NULL;
            SET @ProbeStatus='DESCRIPTION_FAILED';
        END
        ELSE IF NOT EXISTS(SELECT 1 FROM @Description WHERE ColumnName=N'rows')
            SET @ProbeStatus='DESCRIPTION_INCOMPLETE';
        ELSE
        BEGIN
            SET @HasMetadata=CASE WHEN EXISTS(SELECT 1 FROM @Description
                WHERE ColumnName=N'persisted_sample_percent') THEN 1 ELSE 0 END;
            SET @ProbeStatus=CASE WHEN @HasMetadata=1 THEN 'COLUMN_PRESENT' ELSE 'COLUMN_NOT_PRESENT' END;
        END;
    END TRY
    BEGIN CATCH
        SELECT @ProbeStatus='DESCRIPTION_FAILED',@ProbeError=ERROR_NUMBER(),@ProbeMessage=ERROR_MESSAGE();
    END CATCH;

    SELECT @CapabilitiesXml=
    (
        SELECT '1.3.2' AS EngineCodeVersion, SYSUTCDATETIME() AS DetectedAtUTC,
            CONVERT(sysname,SERVERPROPERTY('ServerName')) AS ServerName,
            @Version AS ProductVersion,
            CONVERT(nvarchar(128),SERVERPROPERTY('Edition')) AS Edition,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductLevel')) AS ProductLevel,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductUpdateLevel')) AS ProductUpdateLevel,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductUpdateReference')) AS ProductUpdateReference,
            c.*, @HasMetadata AS HasPersistedSamplePercentMetadata,
            @ProbeStatus AS PersistedMetadataProbeStatus,
            @ProbeError AS MetadataProbeErrorNumber,@ProbeMessage AS MetadataProbeErrorMessage,
            'Feature boundaries, not servicing approval or workload certification.' AS CapabilityNote
        FROM dbo.ufn_DRE_StatsCapabilities_v1(@Version,@Edition) c
        FOR XML PATH('Capabilities'),TYPE
    );
    IF @EmitResult=1
        SELECT @Version AS ProductVersion,
            CONVERT(nvarchar(128),SERVERPROPERTY('Edition')) AS Edition,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductLevel')) AS ProductLevel,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductUpdateLevel')) AS ProductUpdateLevel,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductUpdateReference')) AS ProductUpdateReference,
            c.*, @HasMetadata AS HasPersistedSamplePercentMetadata,
            @ProbeStatus AS PersistedMetadataProbeStatus,
            @ProbeError AS MetadataProbeErrorNumber,@ProbeMessage AS MetadataProbeErrorMessage,
            @CapabilitiesXml AS CapabilitiesXml
        FROM dbo.ufn_DRE_StatsCapabilities_v1(@Version,@Edition) c;
END;
