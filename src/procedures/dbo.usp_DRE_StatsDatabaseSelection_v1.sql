CREATE PROCEDURE dbo.usp_DRE_StatsDatabaseSelection_v1
    @Databases nvarchar(max), @SelectionXml xml=NULL OUTPUT, @EmitResult bit=1
AS
BEGIN
    SET NOCOUNT ON;
    SET @SelectionXml=NULL;
    IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1
        THROW 51020,'Selection preview requires sysadmin to avoid partial database visibility.',1;
    SET @Databases=LTRIM(RTRIM(@Databases));
    IF @Databases IS NULL OR LEN(@Databases)=0
        THROW 51025,'Specify one database, a comma-separated list, or ALL.',1;
    DECLARE @List TABLE(DatabaseID int NOT NULL PRIMARY KEY,DatabaseName sysname COLLATE DATABASE_DEFAULT NOT NULL,
        DatabaseCreateDateLocal datetime2(7) NOT NULL,DatabaseState nvarchar(60) COLLATE DATABASE_DEFAULT NOT NULL,
        IsAccessible bit NOT NULL,IsSnapshot bit NOT NULL,IsExcluded bit NULL,
        EnabledForEnforcement bit NULL,ScopeXml xml NULL);
    IF UPPER(@Databases)=N'ALL'
        INSERT @List(DatabaseID,DatabaseName,DatabaseCreateDateLocal,DatabaseState,IsAccessible,IsSnapshot)
        SELECT database_id,name,create_date,state_desc,1,0 FROM sys.databases
        WHERE database_id>4 AND database_id<>DB_ID() AND state=0
            AND source_database_id IS NULL AND HAS_DBACCESS(name)=1;
    ELSE
    BEGIN
        DECLARE @Tokens TABLE(Name nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL);
        DECLARE @TokenStart int=1,@TokenEnd int;
        WHILE 1=1
        BEGIN
            SET @TokenEnd=CHARINDEX(N',',@Databases,@TokenStart);
            IF @TokenEnd=0
            BEGIN
                INSERT @Tokens(Name) VALUES(LTRIM(RTRIM(SUBSTRING(@Databases,@TokenStart,LEN(@Databases)-@TokenStart+1))));
                BREAK;
            END;
            INSERT @Tokens(Name) VALUES(LTRIM(RTRIM(SUBSTRING(@Databases,@TokenStart,@TokenEnd-@TokenStart))));
            SET @TokenStart=@TokenEnd+1;
        END;
        IF EXISTS(SELECT 1 FROM @Tokens WHERE LEN(Name)=0 OR DATALENGTH(Name)>256)
            THROW 51031,'Database list contains an empty or overlength name. Use unbracketed names, without empty comma tokens.',1;
        IF EXISTS(SELECT 1 FROM @Tokens WHERE UPPER(Name)=N'ALL')
            THROW 51031,'ALL must be used alone. Use persistent database exclusions rather than negative list tokens.',1;
        IF EXISTS(SELECT 1 FROM @Tokens WHERE DB_ID(CONVERT(sysname,Name)) IS NULL)
            THROW 51031,'Database list contains a nonexistent or invisible database name. No database will be processed.',1;
        INSERT @List(DatabaseID,DatabaseName,DatabaseCreateDateLocal,DatabaseState,IsAccessible,IsSnapshot)
        SELECT DISTINCT d.database_id,d.name,d.create_date,d.state_desc,
            CONVERT(bit,ISNULL(HAS_DBACCESS(d.name),0)),CONVERT(bit,CASE WHEN d.source_database_id IS NULL THEN 0 ELSE 1 END)
        FROM @Tokens t JOIN sys.databases d ON d.database_id=DB_ID(CONVERT(sysname,t.Name));
    END;
    IF NOT EXISTS(SELECT 1 FROM @List) THROW 51032,'No databases matched the requested catalog selection.',1;
    DECLARE @ID int=0,@Db sysname,@Scope xml;
    WHILE EXISTS(SELECT 1 FROM @List WHERE DatabaseID>@ID)
    BEGIN
        SELECT TOP(1) @ID=DatabaseID,@Db=DatabaseName FROM @List WHERE DatabaseID>@ID ORDER BY DatabaseID;
        EXEC dbo.usp_DRE_StatsScopeLookup_v1 @Db,@Scope OUTPUT;
        UPDATE @List SET ScopeXml=@Scope,
            IsExcluded=@Scope.value('(/Scope/IsExcluded/text())[1]','bit'),
            EnabledForEnforcement=@Scope.value('(/Scope/EnabledForEnforcement/text())[1]','bit')
        WHERE DatabaseID=@ID;
    END;
    SELECT @SelectionXml=(SELECT DatabaseID,DatabaseName,DatabaseCreateDateLocal,DatabaseState,IsAccessible,IsSnapshot,
        IsExcluded,EnabledForEnforcement,
        CASE WHEN IsExcluded=1 THEN 'EXCLUDED' ELSE 'SELECTED' END AS SelectionStatus,
        CASE WHEN IsExcluded=1 THEN 'PERSISTENT_DATABASE_EXCLUSION' ELSE 'REQUESTED_DATABASE' END AS SelectionReason,
        CONVERT(bit,CASE WHEN DatabaseID>4 AND DatabaseState=N'ONLINE' AND IsAccessible=1 AND IsSnapshot=0 THEN 1 ELSE 0 END) AS ReadyForCollection,
        ScopeXml.query('/Scope')
        FROM @List ORDER BY DatabaseName FOR XML PATH('Database'),ROOT('DatabaseSelection'),TYPE);
    IF @EmitResult=1
        SELECT DatabaseID,DatabaseName,DatabaseState,IsAccessible,IsSnapshot,
            CASE WHEN IsExcluded=1 THEN 'EXCLUDED' ELSE 'SELECTED' END AS SelectionStatus,
            IsExcluded,EnabledForEnforcement,
            CONVERT(bit,CASE WHEN IsExcluded=0 AND DatabaseID>4 AND DatabaseState=N'ONLINE'
                AND IsAccessible=1 AND IsSnapshot=0 THEN 1 ELSE 0 END) AS WillCollect,
            CASE WHEN ScopeXml.exist('/Scope/ExclusionReason[1]')=1
                THEN ScopeXml.value('(/Scope/ExclusionReason/text())[1]','nvarchar(2000)') END AS ExclusionReason,
            ScopeXml
        FROM @List ORDER BY DatabaseName;
END;
