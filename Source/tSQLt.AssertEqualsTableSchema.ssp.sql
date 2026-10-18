IF OBJECT_ID('tSQLt.AssertEqualsTableSchema') IS NOT NULL DROP PROCEDURE tSQLt.AssertEqualsTableSchema;
GO
---Build+
GO
CREATE PROCEDURE tSQLt.AssertEqualsTableSchema
    @Expected NVARCHAR(MAX),
    @Actual NVARCHAR(MAX),
    @Message NVARCHAR(MAX) = NULL
AS
BEGIN
  DECLARE @ExpectedCatalog NVARCHAR(MAX), @ActualCatalog NVARCHAR(MAX);
  SELECT @ExpectedCatalog = CASE WHEN PARSENAME(@Expected,1) LIKE '#%' THEN 'tempdb.' ELSE '' END,
         @ActualCatalog = CASE WHEN PARSENAME(@Actual,1) LIKE '#%' THEN 'tempdb.' ELSE '' END;

  DECLARE @ExpectedObjectId INT, @ActualObjectId INT;
  SELECT @ExpectedObjectId = OBJECT_ID(CASE WHEN @ExpectedCatalog = 'tempdb.' THEN 'tempdb..'+QUOTENAME(PARSENAME(@Expected,1)) ELSE @Expected END),
         @ActualObjectId = OBJECT_ID(CASE WHEN @ActualCatalog = 'tempdb.' THEN 'tempdb..'+QUOTENAME(PARSENAME(@Actual,1)) ELSE @Actual END);

  -- Resolve input IDs before creating the metadata tables, which may have the same names.
  -- Keep both metadata tables and their comparison in the same dynamic SQL scope.
  DECLARE @Cmd NVARCHAR(MAX);
  SET @Cmd = N'
  SELECT 
      RANK()OVER(ORDER BY C.column_id) [RANK(column_id)],
      C.name COLLATE DATABASE_DEFAULT AS name,
      CAST(C.system_type_id AS NVARCHAR(MAX))+QUOTENAME(TS.name) COLLATE DATABASE_DEFAULT system_type_id,
      CAST(C.user_type_id AS NVARCHAR(MAX))+CASE WHEN TU.system_type_id<> TU.user_type_id THEN QUOTENAME(S.name)+''.'' ELSE '''' END + QUOTENAME(TU.name) COLLATE DATABASE_DEFAULT user_type_id,
      C.max_length,
      C.precision,
      C.scale,
      C.collation_name COLLATE DATABASE_DEFAULT AS collation_name,
      C.is_nullable
    INTO #Expected
    FROM '+@ExpectedCatalog+N'sys.columns AS C
    JOIN '+@ExpectedCatalog+N'sys.types AS TS
      ON C.system_type_id = TS.user_type_id
    JOIN '+@ExpectedCatalog+N'sys.types AS TU
      ON C.user_type_id = TU.user_type_id
    JOIN '+@ExpectedCatalog+N'sys.schemas AS S
      ON TU.schema_id = S.schema_id
   WHERE C.object_id = @ExpectedObjectId;
  SELECT 
      RANK()OVER(ORDER BY C.column_id) [RANK(column_id)],
      C.name COLLATE DATABASE_DEFAULT AS name,
      CAST(C.system_type_id AS NVARCHAR(MAX))+QUOTENAME(TS.name) COLLATE DATABASE_DEFAULT system_type_id,
      CAST(C.user_type_id AS NVARCHAR(MAX))+CASE WHEN TU.system_type_id<> TU.user_type_id THEN QUOTENAME(S.name)+''.'' ELSE '''' END + QUOTENAME(TU.name) COLLATE DATABASE_DEFAULT user_type_id,
      C.max_length,
      C.precision,
      C.scale,
      C.collation_name COLLATE DATABASE_DEFAULT AS collation_name,
      C.is_nullable
    INTO #Actual
    FROM '+@ActualCatalog+N'sys.columns AS C
    JOIN '+@ActualCatalog+N'sys.types AS TS
      ON C.system_type_id = TS.user_type_id
    JOIN '+@ActualCatalog+N'sys.types AS TU
      ON C.user_type_id = TU.user_type_id
    JOIN '+@ActualCatalog+N'sys.schemas AS S
      ON TU.schema_id = S.schema_id
   WHERE C.object_id = @ActualObjectId;

  EXEC tSQLt.AssertEqualsTable ''#Expected'',''#Actual'',@Message=@Message,@FailMsg=''Unexpected/missing column(s)'';';
  EXEC sys.sp_executesql @Cmd,
       N'@ExpectedObjectId INT, @ActualObjectId INT, @Message NVARCHAR(MAX)',
       @ExpectedObjectId, @ActualObjectId, @Message;
END;
GO