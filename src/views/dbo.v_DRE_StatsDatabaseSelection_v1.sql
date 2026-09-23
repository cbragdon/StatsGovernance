CREATE VIEW dbo.v_DRE_StatsDatabaseSelection_v1
AS
SELECT d.RunID,r.EngineVersion,r.Mode,r.RunStatus,d.DatabaseName,
    d.DatabaseIDAtSelection,d.DatabaseCreateDateAtSelection,d.SelectionStatus,d.SelectionReason,
    d.CollectionStatus,d.CandidateCount,d.LastScopeStatus,d.LastScopeCheckAtUTC,
    CASE WHEN d.ScopeAtSelectionXml.exist('/Scope/IsExcluded[1]')=1
        THEN d.ScopeAtSelectionXml.value('(/Scope/IsExcluded/text())[1]','bit') END AS InitiallyExcluded,
    CASE WHEN d.ScopeAtSelectionXml.exist('/Scope/ExclusionReason[1]')=1
        THEN d.ScopeAtSelectionXml.value('(/Scope/ExclusionReason/text())[1]','nvarchar(2000)') END AS InitialExclusionReason,
    CASE WHEN d.ScopeAtLastCheckXml.exist('/Scope/ExclusionReason[1]')=1
        THEN d.ScopeAtLastCheckXml.value('(/Scope/ExclusionReason/text())[1]','nvarchar(2000)') END AS LastExclusionReason,
    CASE WHEN d.ScopeAtLastCheckXml.exist('/Scope/ExcludedBy[1]')=1
        THEN d.ScopeAtLastCheckXml.value('(/Scope/ExcludedBy/text())[1]','nvarchar(128)') END AS ExcludedBy,
    CASE WHEN d.ScopeAtLastCheckXml.exist('/Scope/ExcludedAtUTC[1]')=1
        THEN d.ScopeAtLastCheckXml.value('(/Scope/ExcludedAtUTC/text())[1]','datetime2(7)') END AS ExcludedAtUTC,
    CASE WHEN d.ScopeAtLastCheckXml.exist('/Scope/EnabledForEnforcement[1]')=1
        THEN d.ScopeAtLastCheckXml.value('(/Scope/EnabledForEnforcement/text())[1]','bit') END AS LastEnforcementApproval,
    d.ErrorNumber,d.ErrorMessage,d.ScopeAtSelectionXml,d.ScopeAtLastCheckXml,d.EnvironmentXml
FROM dbo.StatsGovernanceRunDatabases d JOIN dbo.StatsGovernanceRuns r ON r.RunID=d.RunID;
