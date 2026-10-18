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
    DECLARE @ReturnCode INT, @CallCount BIGINT, @QuotedProcedureName NVARCHAR(MAX);
    EXEC @ReturnCode = tSQLt.Private_GetSpyProcedureCallCount
      @ProcedureName, @CallCount OUTPUT, @QuotedProcedureName OUTPUT;
    IF @ReturnCode <> 0 RETURN;
    DECLARE @ProcedureObjectId INT = OBJECT_ID(@QuotedProcedureName);
    DECLARE @Log NVARCHAR(MAX) = QUOTENAME(OBJECT_SCHEMA_NAME(@ProcedureObjectId)) + '.' +
                               QUOTENAME(OBJECT_NAME(@ProcedureObjectId) + '_SpyProcedureLog');
    DECLARE @LogIdentityColumn SYSNAME;
    SELECT @LogIdentityColumn = name FROM sys.columns WHERE object_id = OBJECT_ID(@Log) AND is_identity = 1;
    IF @IgnoreOrder IS NULL
    BEGIN
      RAISERROR('AssertProcedureCalls: @IgnoreOrder must be 0 or 1.',16,10);
      RETURN;
    END;

    -- Resolve identifiers before using them in dynamic SQL, including local temp tables.
    IF PARSENAME(@Expected,4) IS NOT NULL
       OR (PARSENAME(@Expected,3) IS NOT NULL AND PARSENAME(@Expected,3) <> DB_NAME())
    BEGIN
      RAISERROR('AssertProcedureCalls: expected table must be in the current database or a local temporary table.',16,10);
      RETURN;
    END;
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

    DECLARE @Columns TABLE(name SYSNAME, column_id INT, CollationName SYSNAME NULL);
    INSERT INTO @Columns(name, column_id)
      SELECT name, column_id FROM sys.columns WHERE @IsTemp = 0 AND object_id = @ExpectedId
      UNION ALL
      SELECT name, column_id FROM tempdb.sys.columns WHERE @IsTemp = 1 AND object_id = @ExpectedId;
    IF EXISTS(SELECT 1 FROM @Columns C WHERE C.name <> '_id_' AND NOT EXISTS
                (SELECT 1 FROM sys.columns L WHERE L.object_id = OBJECT_ID(@Log) AND L.name = C.name AND L.is_identity = 0))
    BEGIN
      RAISERROR('AssertProcedureCalls: expected table contains an unknown argument column.',16,10);
      RETURN;
    END;
    IF @IgnoreOrder = 0 AND NOT EXISTS(SELECT 1 FROM @Columns WHERE name = '_id_')
    BEGIN
      RAISERROR('AssertProcedureCalls: ordered expectations require a unique, non-NULL _id_ column.',16,10);
      RETURN;
    END;

    -- Temporary expectations can inherit a different tempdb collation. Compare
    -- text using the log column's collation, including its case sensitivity.
    UPDATE C SET CollationName = L.collation_name FROM @Columns C
      JOIN sys.columns L ON L.object_id = OBJECT_ID(@Log) AND L.name = C.name;

    DECLARE @ColumnList NVARCHAR(MAX);
    SELECT @ColumnList = STUFF((SELECT ',' + QUOTENAME(name) +
                                 CASE WHEN CollationName IS NULL THEN '' ELSE ' COLLATE ' + QUOTENAME(CollationName) END + ' AS ' + QUOTENAME(name)
                               FROM @Columns WHERE name <> '_id_'
                               ORDER BY column_id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,'');
    DECLARE @LogColumnList NVARCHAR(MAX);
    SELECT @LogColumnList = STUFF((SELECT ',L.' + QUOTENAME(name) +
                                    CASE WHEN CollationName IS NULL THEN '' ELSE ' COLLATE ' + QUOTENAME(CollationName) END + ' AS ' + QUOTENAME(name)
                                  FROM @Columns WHERE name <> '_id_'
                                  ORDER BY column_id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,'');
    DECLARE @Projection NVARCHAR(MAX) = ISNULL(@ColumnList, '');
    IF @IgnoreOrder = 0
      SET @Projection = 'ROW_NUMBER() OVER(ORDER BY [_id_]) AS [_id_]' + CASE WHEN @Projection = '' THEN '' ELSE ',' + @Projection END;
    -- With no selected arguments, a constant still preserves call multiplicity.
    IF @Projection = '' SET @Projection = 'CAST(1 AS INT) AS [_id_]';
    DECLARE @ActualProjection NVARCHAR(MAX) = ISNULL(@LogColumnList, '');
    IF @IgnoreOrder = 0
      SET @ActualProjection = 'ROW_NUMBER() OVER(ORDER BY ' + QUOTENAME(@LogIdentityColumn) + ') AS [_id_]' +
        CASE WHEN @LogColumnList IS NULL THEN '' ELSE ',' + @LogColumnList END;
    IF @ActualProjection = '' SET @ActualProjection = 'CAST(1 AS INT) AS [_id_]';

    DECLARE @Sql NVARCHAR(MAX) = '';
    IF @IgnoreOrder = 0
      SET @Sql = 'IF EXISTS(SELECT [_id_] FROM ' + @Expected + ' GROUP BY [_id_] HAVING [_id_] IS NULL OR COUNT_BIG(*) > 1)
        BEGIN RAISERROR(''AssertProcedureCalls: ordered expectations require a unique, non-NULL _id_ column.'',16,10); RETURN; END;';
    IF @CalledWith = 1
      SET @Sql = @Sql + 'IF (SELECT COUNT_BIG(*) FROM ' + @Expected + ') <> 1
        BEGIN RAISERROR(''AssertProcedureCalledWith: expected table must contain exactly one row.'',16,10); RETURN; END;';
    SET @Sql = @Sql + 'SELECT ' + @Projection + ' INTO #tSQLt_ExpectedProcedureCalls FROM ' + @Expected + ';
      SELECT ' + CASE WHEN @CalledWith = 1 THEN 'TOP(1) ' ELSE '' END + @ActualProjection +
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
