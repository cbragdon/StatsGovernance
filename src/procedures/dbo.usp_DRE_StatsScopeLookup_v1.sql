
CREATE PROCEDURE dbo.usp_DRE_StatsScopeLookup_v1
    @DatabaseName sysname,
    @ScopeXml xml OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @ScopeXml = NULL;

    DECLARE
        @DatabaseID int = DB_ID(@DatabaseName),
        @Matches int;

    IF @DatabaseID IS NULL
        THROW 51050,'The scope target database does not exist or is not visible.',1;

    -- Capture once: count and decision use the same configuration snapshot.
    -- Explicit NULL/NOT NULL is intentional. sysname otherwise defaults to NOT NULL.
    DECLARE @ScopeRows TABLE
    (
        DatabaseName sysname COLLATE DATABASE_DEFAULT NOT NULL,
        IsExcluded bit NOT NULL,
        ExclusionReason nvarchar(2000) COLLATE DATABASE_DEFAULT NULL,
        ExcludedBy sysname COLLATE DATABASE_DEFAULT NULL,
        ExcludedAtUTC datetime2(7) NULL,
        EnabledForEnforcement bit NOT NULL,
        ApprovedBy sysname COLLATE DATABASE_DEFAULT NULL,
        ApprovedAtUTC datetime2(7) NULL,
        Notes nvarchar(2000) COLLATE DATABASE_DEFAULT NOT NULL,
        Revision binary(8) NOT NULL
    );

    INSERT @ScopeRows
    (
        DatabaseName,
        IsExcluded,
        ExclusionReason,
        ExcludedBy,
        ExcludedAtUTC,
        EnabledForEnforcement,
        ApprovedBy,
        ApprovedAtUTC,
        Notes,
        Revision
    )
    SELECT
        DatabaseName,
        IsExcluded,
        ExclusionReason,
        ExcludedBy,
        ExcludedAtUTC,
        EnabledForEnforcement,
        ApprovedBy,
        ApprovedAtUTC,
        Notes,
        Revision
    FROM dbo.StatsGovernanceScope
    WHERE DB_ID(DatabaseName) = @DatabaseID;

    SELECT @Matches = COUNT(*)
    FROM @ScopeRows;

    IF @Matches > 1
        THROW 51051,'Multiple scope entries resolve to the same database. Resolve conflicting aliases before proceeding.',1;

    SELECT @ScopeXml =
    (
        SELECT
            DB_NAME(@DatabaseID) AS DatabaseName,
            @DatabaseID AS DatabaseID,
            s.DatabaseName AS ConfiguredDatabaseName,
            CONVERT(bit,CASE WHEN s.DatabaseName IS NULL THEN 0 ELSE 1 END) AS IsConfigured,
            ISNULL(s.IsExcluded,CONVERT(bit,0)) AS IsExcluded,
            s.ExclusionReason,
            s.ExcludedBy,
            s.ExcludedAtUTC,
            ISNULL(s.EnabledForEnforcement,CONVERT(bit,0)) AS EnabledForEnforcement,
            s.ApprovedBy,
            s.ApprovedAtUTC,
            s.Notes,
            sys.fn_varbintohexstr(s.Revision) AS Revision,
            SYSUTCDATETIME() AS CheckedAtUTC
        FROM (VALUES(1)) AS v(n)
        LEFT JOIN @ScopeRows AS s ON 1=1
        FOR XML PATH('Scope'),TYPE
    );
END;
