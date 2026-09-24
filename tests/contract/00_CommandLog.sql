/* Verifies the installer-owned bootstrap contract for the shared Ola-compatible CommandLog table. */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Expected TABLE
(
    ColumnName sysname COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY,
    TypeID tinyint NOT NULL,
    MaxLength smallint NOT NULL,
    IsNullable bit NOT NULL
);
INSERT @Expected(ColumnName,TypeID,MaxLength,IsNullable)
VALUES
(N'ID',56,4,0),(N'DatabaseName',231,256,1),(N'SchemaName',231,256,1),
(N'ObjectName',231,256,1),(N'ObjectType',175,2,1),(N'IndexName',231,256,1),
(N'IndexType',48,1,1),(N'StatisticsName',231,256,1),(N'PartitionNumber',56,4,1),
(N'ExtendedInfo',241,-1,1),(N'Command',231,-1,0),(N'CommandType',231,120,0),
(N'StartTime',42,8,0),(N'EndTime',42,8,1),(N'ErrorNumber',56,4,1),
(N'ErrorMessage',231,-1,1);

IF OBJECT_ID(N'dbo.CommandLog',N'U') IS NULL
    THROW 51690,'dbo.CommandLog was not created.',1;

IF EXISTS
(
    SELECT 1
    FROM @Expected AS e
    LEFT JOIN sys.columns AS c
      ON c.object_id=OBJECT_ID(N'dbo.CommandLog',N'U')
     AND c.name COLLATE Latin1_General_100_BIN2=e.ColumnName
    WHERE c.column_id IS NULL
       OR c.system_type_id<>e.TypeID
       OR c.max_length<>e.MaxLength
       OR c.is_nullable<>e.IsNullable
)
    THROW 51691,'dbo.CommandLog has a missing or incompatible required column.',1;

IF COLUMNPROPERTY(OBJECT_ID(N'dbo.CommandLog',N'U'),N'ID','IsIdentity')<>1
    THROW 51692,'dbo.CommandLog.ID must be an identity column.',1;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    JOIN sys.index_columns AS ic
      ON ic.object_id=i.object_id AND ic.index_id=i.index_id
    JOIN sys.columns AS c
      ON c.object_id=ic.object_id AND c.column_id=ic.column_id
    WHERE i.object_id=OBJECT_ID(N'dbo.CommandLog',N'U')
      AND i.is_primary_key=1
      AND i.type=1
      AND ic.key_ordinal=1
      AND c.name=N'ID'
      AND NOT EXISTS
          (SELECT 1 FROM sys.index_columns AS x
           WHERE x.object_id=i.object_id AND x.index_id=i.index_id AND x.key_ordinal>1)
)
    THROW 51693,'dbo.CommandLog must have a clustered primary key on ID.',1;

SELECT N'COMMANDLOG_CONTRACT_PASS' AS Status;
