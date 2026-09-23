CREATE TRIGGER dbo.tr_DRE_StatsScopeAudit_v1
ON dbo.StatsGovernanceScope
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
    -- A key change is a different database configuration, not a scope edit.
    IF UPDATE(DatabaseName) AND EXISTS(SELECT 1 FROM deleted)
        THROW 51060, 'Do not rename a scope key. Review and create the new database configuration explicitly.',1;
    INSERT dbo.StatsGovernanceScopeAudit
        (DatabaseName,ChangeType,ChangedAtUTC,ChangedBy,SessionID,OldScopeXml,NewScopeXml)
    SELECT COALESCE(i.DatabaseName,d.DatabaseName),
        CASE WHEN d.DatabaseName IS NULL THEN 'INSERT'
             WHEN i.DatabaseName IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
        SYSUTCDATETIME(),ORIGINAL_LOGIN(),@@SPID,
        CASE WHEN d.DatabaseName IS NOT NULL THEN
            (SELECT d.DatabaseName,d.IsExcluded,d.ExclusionReason,d.ExcludedBy,d.ExcludedAtUTC,
                d.EnabledForEnforcement,d.ApprovedBy,d.ApprovedAtUTC,d.Notes,
                sys.fn_varbintohexstr(d.Revision) AS Revision FOR XML PATH('Scope'),TYPE) END,
        CASE WHEN i.DatabaseName IS NOT NULL THEN
            (SELECT i.DatabaseName,i.IsExcluded,i.ExclusionReason,i.ExcludedBy,i.ExcludedAtUTC,
                i.EnabledForEnforcement,i.ApprovedBy,i.ApprovedAtUTC,i.Notes,
                sys.fn_varbintohexstr(i.Revision) AS Revision FOR XML PATH('Scope'),TYPE) END
    FROM inserted i FULL JOIN deleted d ON d.DatabaseName=i.DatabaseName;
END;
