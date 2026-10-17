IF OBJECT_ID('tSQLt.Private_AssertProcedureCalls') IS NOT NULL DROP PROCEDURE tSQLt.Private_AssertProcedureCalls;
GO
---Build+
CREATE PROCEDURE tSQLt.Private_AssertProcedureCalls
    @ProcedureName NVARCHAR(MAX),
    @Expected NVARCHAR(MAX),
    @IgnoreOrder BIT,
    @Message NVARCHAR(MAX),
    @CalledWith BIT = 0
AS
BEGIN
    DECLARE @ProcedureObjectId INT = OBJECT_ID(@ProcedureName);
    DECLARE @Log NVARCHAR(MAX) = QUOTENAME(OBJECT_SCHEMA_NAME(@ProcedureObjectId)) + '.' +
                               QUOTENAME(OBJECT_NAME(@ProcedureObjectId) + '_SpyProcedureLog');
    IF @Log IS NULL OR OBJECT_ID(@Log, 'U') IS NULL
    BEGIN
      RAISERROR('AssertProcedureCalls: procedure must have a SpyProcedure log.',16,10);
      RETURN;
    END;
    IF @IgnoreOrder IS NULL
    BEGIN
      RAISERROR('AssertProcedureCalls: @IgnoreOrder must be 0 or 1.',16,10);
      RETURN;
    END;

    -- Resolve identifiers before using them in dynamic SQL, including local temp tables.
    DECLARE @ExpectedId INT;
    DECLARE @ExpectedName SYSNAME = PARSENAME(@Expected,1);
    DECLARE @IsTemp BIT = CASE WHEN LEFT(@ExpectedName,1) = '#' THEN 1 ELSE 0 END;
    SET @ExpectedId = CASE WHEN @IsTemp = 1 THEN OBJECT_ID('tempdb..' + QUOTENAME(@ExpectedName), 'U')
                          ELSE OBJECT_ID(@Expected, 'U') END;
    IF @ExpectedId IS NULL
    BEGIN
      RAISERROR('AssertProcedureCalls: expected table does not exist.',16,10);
      RETURN;
    END;
    SET @Expected = CASE WHEN @IsTemp = 1 THEN QUOTENAME(@ExpectedName)
                        ELSE QUOTENAME(OBJECT_SCHEMA_NAME(@ExpectedId)) + '.' + QUOTENAME(OBJECT_NAME(@ExpectedId)) END;

    DECLARE @Columns TABLE(name SYSNAME, column_id INT);
    INSERT INTO @Columns
      SELECT name, column_id FROM sys.columns WHERE @IsTemp = 0 AND object_id = @ExpectedId
      UNION ALL
      SELECT name, column_id FROM tempdb.sys.columns WHERE @IsTemp = 1 AND object_id = @ExpectedId;
    IF EXISTS(SELECT 1 FROM @Columns C WHERE C.name <> '_id_' AND NOT EXISTS
                (SELECT 1 FROM sys.columns L WHERE L.object_id = OBJECT_ID(@Log) AND L.name = C.name))
    BEGIN
      RAISERROR('AssertProcedureCalls: expected table contains an unknown argument column.',16,10);
      RETURN;
    END;
    IF @IgnoreOrder = 0 AND NOT EXISTS(SELECT 1 FROM @Columns WHERE name = '_id_')
    BEGIN
      RAISERROR('AssertProcedureCalls: ordered expectations require a unique, non-NULL _id_ column.',16,10);
      RETURN;
    END;

    DECLARE @ColumnList NVARCHAR(MAX);
    SELECT @ColumnList = STUFF((SELECT ',' + QUOTENAME(name) FROM @Columns WHERE name <> '_id_'
                               ORDER BY column_id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,'');
    DECLARE @LogColumnList NVARCHAR(MAX);
    SELECT @LogColumnList = STUFF((SELECT ',L.' + QUOTENAME(name) FROM @Columns WHERE name <> '_id_'
                                  ORDER BY column_id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,'');
    DECLARE @Projection NVARCHAR(MAX) = ISNULL(@ColumnList, '');
    IF @IgnoreOrder = 0
      SET @Projection = 'ROW_NUMBER() OVER(ORDER BY [_id_]) AS [_id_]' + CASE WHEN @Projection = '' THEN '' ELSE ',' + @Projection END;
    -- With no selected arguments, a constant still preserves call multiplicity.
    IF @Projection = '' SET @Projection = 'CAST(1 AS INT) AS [_id_]';

    DECLARE @Sql NVARCHAR(MAX) = '';
    IF @IgnoreOrder = 0
      SET @Sql = 'IF EXISTS(SELECT [_id_] FROM ' + @Expected + ' GROUP BY [_id_] HAVING [_id_] IS NULL OR COUNT_BIG(*) > 1)
        BEGIN RAISERROR(''AssertProcedureCalls: ordered expectations require a unique, non-NULL _id_ column.'',16,10); RETURN; END;';
    IF @CalledWith = 1
      SET @Sql = @Sql + 'IF (SELECT COUNT_BIG(*) FROM ' + @Expected + ') <> 1
        BEGIN RAISERROR(''AssertProcedureCalledWith: expected table must contain exactly one row.'',16,10); RETURN; END;';
    SET @Sql = @Sql + 'SELECT ' + @Projection + ' INTO #tSQLt_ExpectedProcedureCalls FROM ' + @Expected + ';
      SELECT ' + CASE WHEN @CalledWith = 1 THEN 'TOP(1) ' ELSE '' END + @Projection +
      ' INTO #tSQLt_ActualProcedureCalls FROM ' + @Log + ' AS L' +
      CASE WHEN @CalledWith = 1 AND @ColumnList IS NOT NULL THEN
        ' WHERE EXISTS(SELECT ' + @ColumnList + ' FROM ' + @Expected +
        ' INTERSECT SELECT ' + @LogColumnList + ')' ELSE '' END + ';
      EXEC tSQLt.AssertEqualsTable ''#tSQLt_ExpectedProcedureCalls'', ''#tSQLt_ActualProcedureCalls'',
        @Message=@Message, @FailMsg=N''Procedure calls differ (< missing expected call; > extra actual call).'';';
    EXEC sys.sp_executesql @Sql, N'@Message NVARCHAR(MAX)', @Message;
END;
---Build-
GO
