CREATE PROCEDURE dbo.usp_DRE_SetStatsDatabaseScope_v1
    @DatabaseName nvarchar(4000),
    @IsExcluded bit=NULL,
    @EnabledForEnforcement bit=NULL,
    @Notes nvarchar(max)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1
        THROW 51052,'Scope configuration requires sysadmin.',1;
    IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2
        THROW 51053,'Configure scope outside an explicit transaction with IMPLICIT_TRANSACTIONS OFF.',1;
    SET @DatabaseName=LTRIM(RTRIM(@DatabaseName));
    SET @Notes=LTRIM(RTRIM(@Notes));
    IF @DatabaseName IS NULL OR LEN(@DatabaseName)=0 OR DATALENGTH(@DatabaseName)>256
        THROW 51054,'Specify one database name of at most 128 UTF-16 code units.',1;
    IF @Notes IS NULL OR LEN(@Notes)=0 OR DATALENGTH(@Notes)>4000
        THROW 51055,'A nonempty change reason of at most 2000 UTF-16 code units is required.',1;
    IF @IsExcluded IS NULL AND @EnabledForEnforcement IS NULL
        THROW 51056,'Specify IsExcluded or EnabledForEnforcement; NULL flags leave existing choices unchanged.',1;
    DECLARE @DatabaseID int=DB_ID(@DatabaseName),@CanonicalName sysname,
        @ConfigName sysname,@OldExcluded bit=0,@OldEnabled bit=0,
        @NewExcluded bit,@NewEnabled bit,@ApprovedBy sysname,@ApprovedAt datetime2(7),
        @ExcludedBy sysname,@ExcludedAt datetime2(7),@ExclusionReason nvarchar(2000),
        @Now datetime2(7)=SYSUTCDATETIME(),@LockResult int,@ScopeXml xml;
    SELECT @CanonicalName=name FROM sys.databases
    WHERE database_id=@DatabaseID AND database_id<>2 AND name<>N'SSISDB'
      AND is_distributor=0 AND source_database_id IS NULL;
    IF @CanonicalName IS NULL
        THROW 51057,'Configure an existing, non-snapshot supported database. tempdb, SSISDB, and replication distribution databases are excluded.',1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC @LockResult=sys.sp_getapplock @Resource=N'DRE.StatsGovernance.v1.SCOPE_CONFIGURATION',
            @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=5000,@DbPrincipal='public';
        IF @LockResult<0 THROW 51058,'Scope configuration lock was not acquired. No scope change was made.',1;
        -- HOLDLOCK/UPDLOCK also serializes the read/write decision with normal DML.
        IF (SELECT COUNT(*) FROM dbo.StatsGovernanceScope WITH(UPDLOCK,HOLDLOCK)
            WHERE DB_ID(DatabaseName)=@DatabaseID)>1
            THROW 51051,'Multiple scope entries resolve to the same database. Resolve conflicting aliases before proceeding.',1;
        SELECT @ConfigName=DatabaseName,@OldExcluded=IsExcluded,@OldEnabled=EnabledForEnforcement,
            @ApprovedBy=ApprovedBy,@ApprovedAt=ApprovedAtUTC,
            @ExcludedBy=ExcludedBy,@ExcludedAt=ExcludedAtUTC,@ExclusionReason=ExclusionReason
        FROM dbo.StatsGovernanceScope WITH(UPDLOCK,HOLDLOCK) WHERE DB_ID(DatabaseName)=@DatabaseID;
        SELECT @NewExcluded=COALESCE(@IsExcluded,@OldExcluded),
               @NewEnabled=COALESCE(@EnabledForEnforcement,@OldEnabled);
        IF @NewExcluded=1
        BEGIN
            IF @EnabledForEnforcement=1 THROW 51059,'An excluded database cannot be approved for enforcement. Remove the exclusion explicitly first.',1;
            SELECT @NewEnabled=0,@ApprovedBy=NULL,@ApprovedAt=NULL,
                   @ExcludedBy=ORIGINAL_LOGIN(),@ExcludedAt=@Now,@ExclusionReason=CONVERT(nvarchar(2000),@Notes);
        END
        ELSE
        BEGIN
            SELECT @ExcludedBy=NULL,@ExcludedAt=NULL,@ExclusionReason=NULL;
            IF @OldExcluded=1 AND @EnabledForEnforcement IS NULL SET @NewEnabled=0;
            IF @NewEnabled=0 SELECT @ApprovedBy=NULL,@ApprovedAt=NULL;
            ELSE IF @EnabledForEnforcement=1 OR @OldEnabled=0
                SELECT @ApprovedBy=ORIGINAL_LOGIN(),@ApprovedAt=@Now;
        END;
        IF @ConfigName IS NULL
            INSERT dbo.StatsGovernanceScope(DatabaseName,EnabledForEnforcement,ApprovedBy,ApprovedAtUTC,Notes,
                IsExcluded,ExclusionReason,ExcludedBy,ExcludedAtUTC)
            VALUES(@CanonicalName,@NewEnabled,@ApprovedBy,@ApprovedAt,CONVERT(nvarchar(2000),@Notes),
                @NewExcluded,@ExclusionReason,@ExcludedBy,@ExcludedAt);
        ELSE
            UPDATE dbo.StatsGovernanceScope SET EnabledForEnforcement=@NewEnabled,
                ApprovedBy=@ApprovedBy,ApprovedAtUTC=@ApprovedAt,Notes=CONVERT(nvarchar(2000),@Notes),
                IsExcluded=@NewExcluded,ExclusionReason=@ExclusionReason,ExcludedBy=@ExcludedBy,ExcludedAtUTC=@ExcludedAt
            WHERE DatabaseName=@ConfigName COLLATE Latin1_General_100_BIN2;
        -- Validate the readback while the change is still reversible.
        EXEC dbo.usp_DRE_StatsScopeLookup_v1 @CanonicalName,@ScopeXml OUTPUT;
        IF @ScopeXml IS NULL
            THROW 51061,'Scope readback returned no contract; the change was rolled back.',1;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
    SELECT @CanonicalName AS DatabaseName,@NewExcluded AS IsExcluded,@NewEnabled AS EnabledForEnforcement,
        @ScopeXml AS CurrentScopeXml;
END;
