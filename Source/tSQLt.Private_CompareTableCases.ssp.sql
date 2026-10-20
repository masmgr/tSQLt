IF OBJECT_ID('tSQLt.Private_CompareTableCases') IS NOT NULL DROP PROCEDURE tSQLt.Private_CompareTableCases;
GO
---Build+
CREATE PROCEDURE tSQLt.Private_CompareTableCases
  @TableName NVARCHAR(MAX),
  @CaseIdColumn NVARCHAR(MAX),
  @ExpectedColumn NVARCHAR(MAX),
  @ActualColumn NVARCHAR(MAX),
  @ExactStrings BIT,
  @ResultTable NVARCHAR(MAX)
AS
BEGIN
  DECLARE @Name SYSNAME=PARSENAME(@TableName,1), @Id INT, @Temp BIT,
          @Sql NVARCHAR(MAX), @Predicate NVARCHAR(MAX), @Inputs NVARCHAR(MAX),
          @Case NVARCHAR(258), @Expected NVARCHAR(258), @Actual NVARCHAR(258);
  IF @TableName IS NULL OR @Name IS NULL OR PARSENAME(@TableName,3) IS NOT NULL
     OR PARSENAME(@TableName,4) IS NOT NULL OR LEFT(@Name,2)=N'##'
    GOTO InvalidTable;
  SET @Temp=CASE WHEN LEFT(@Name,1)=N'#' THEN 1 ELSE 0 END;
  IF @Temp=1 AND PARSENAME(@TableName,2) IS NOT NULL GOTO InvalidTable;
  SET @Id=CASE WHEN @Temp=1 THEN OBJECT_ID(N'tempdb..'+QUOTENAME(@Name),N'U')
               ELSE OBJECT_ID(@TableName,N'U') END;
  IF @Id IS NULL GOTO InvalidTable;
  SET @TableName=CASE WHEN @Temp=1 THEN QUOTENAME(@Name)
                     ELSE QUOTENAME(OBJECT_SCHEMA_NAME(@Id))+N'.'+QUOTENAME(OBJECT_NAME(@Id)) END;
  DECLARE @Columns TABLE(Ordinal INT, Name SYSNAME COLLATE DATABASE_DEFAULT, TypeId INT,
    UserTypeId INT, MaxLength SMALLINT, PrecisionValue TINYINT, ScaleValue TINYINT,
    CollationName SYSNAME COLLATE DATABASE_DEFAULT NULL);
  INSERT @Columns
    SELECT column_id,name COLLATE DATABASE_DEFAULT,system_type_id,user_type_id,max_length,precision,scale,collation_name COLLATE DATABASE_DEFAULT
      FROM sys.columns WHERE @Temp=0 AND object_id=@Id
    UNION ALL
    SELECT column_id,name COLLATE DATABASE_DEFAULT,system_type_id,user_type_id,max_length,precision,scale,collation_name COLLATE DATABASE_DEFAULT
      FROM tempdb.sys.columns WHERE @Temp=1 AND object_id=@Id;
  IF NOT EXISTS(SELECT 1 FROM @Columns WHERE Name=@CaseIdColumn AND TypeId IN(167,175,231,239))
     OR NOT EXISTS(SELECT 1 FROM @Columns WHERE Name=@ExpectedColumn)
     OR NOT EXISTS(SELECT 1 FROM @Columns WHERE Name=@ActualColumn)
     OR @ExactStrings IS NULL
  BEGIN
    RAISERROR('AssertTableCases: invalid columns, non-string CaseId, or NULL @ExactStrings.',16,10);
    RETURN;
  END;
  IF NOT EXISTS(SELECT 1 FROM @Columns E JOIN @Columns A
      ON E.TypeId=A.TypeId AND E.UserTypeId=A.UserTypeId AND E.MaxLength=A.MaxLength
     AND E.PrecisionValue=A.PrecisionValue AND E.ScaleValue=A.ScaleValue
     AND (@ExactStrings=1 OR ISNULL(E.CollationName,N'')=ISNULL(A.CollationName,N''))
      WHERE E.Name=@ExpectedColumn AND A.Name=@ActualColumn
        AND E.TypeId IN(36,40,41,42,43,48,52,56,58,59,60,61,62,104,106,108,122,127,165,167,173,175,231,239)
        AND (@ExactStrings=0 OR E.TypeId IN(167,175,231,239)))
  BEGIN
    RAISERROR('AssertTableCases: Expected and Actual require identical comparable types and compatible collations; exact comparison requires strings.',16,10);
    RETURN;
  END;
  SELECT @Case=QUOTENAME(@CaseIdColumn),@Expected=QUOTENAME(@ExpectedColumn),@Actual=QUOTENAME(@ActualColumn);
  SET @Sql=N'IF NOT EXISTS(SELECT 1 FROM '+@TableName+N')
      RAISERROR(''AssertTableCases: the input table is empty.'',16,10);
    IF EXISTS(SELECT 1 FROM '+@TableName+N' WHERE '+@Case+N' IS NULL
      OR DATALENGTH(CONVERT(NVARCHAR(MAX),'+@Case+N')) NOT BETWEEN 2 AND 256)
      RAISERROR(''AssertTableCases: CaseId must contain 1 to 128 UTF-16 units.'',16,10);
    IF EXISTS(SELECT 1 FROM '+@TableName+N'
      GROUP BY DATALENGTH(CONVERT(NVARCHAR(MAX),'+@Case+N')),CONVERT(VARBINARY(256),CONVERT(NVARCHAR(MAX),'+@Case+N'))
      HAVING COUNT_BIG(*)>1)
      RAISERROR(''AssertTableCases: duplicate CaseId.'',16,10);';
  EXEC sys.sp_executesql @Sql;
  SET @Predicate=CASE WHEN @ExactStrings=1
    THEN N'(SELECT IsEqual FROM tSQLt.Private_CompareStringExact(CONVERT(NVARCHAR(MAX),'+@Expected+N'),CONVERT(NVARCHAR(MAX),'+@Actual+N')))'
    ELSE N'CASE WHEN '+@Expected+N'='+@Actual+N' OR ('+@Expected+N' IS NULL AND '+@Actual+N' IS NULL) THEN 1 ELSE 0 END' END;
  -- Diagnostics are separate from equality. Unsupported descriptive types are named,
  -- not implicitly converted (which could make an otherwise valid assertion error).
  SELECT @Inputs=(SELECT N'+N''; '+REPLACE(Name,N'''',N'''''')+N'=''+'
    +CASE WHEN TypeId IN(34,35,99,240,241) THEN N'N''<unformatted>'''
          ELSE N'COALESCE(LEFT(CONVERT(NVARCHAR(MAX),'+QUOTENAME(Name)+N'),256),N''NULL'')' END
      FROM @Columns WHERE Name NOT IN(@CaseIdColumn,@ExpectedColumn,@ActualColumn)
      ORDER BY Ordinal FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)');
  DECLARE @Type INT;
  SELECT @Type=TypeId FROM @Columns WHERE Name=@ExpectedColumn;
  DECLARE @Style NVARCHAR(10)=CASE WHEN @Type IN(60,122,59,62) THEN N',2'
    WHEN @Type IN(58,61) THEN N',121' WHEN @Type IN(165,173) THEN N',1' ELSE N'' END;
  SET @Sql=N'INSERT '+@ResultTable+N'(CaseId,IsEqual,ExpectedValue,ActualValue,Inputs)
    SELECT CONVERT(NVARCHAR(128),'+@Case+N'),'+@Predicate+N',
      CONVERT(NVARCHAR(MAX),'+@Expected+@Style+N'),CONVERT(NVARCHAR(MAX),'+@Actual+@Style+N'),
      N'''''+ISNULL(@Inputs,N'')+N' FROM '+@TableName+N';';
  EXEC sys.sp_executesql @Sql;
  RETURN;
InvalidTable:
  RAISERROR('AssertTableCases: specify an existing table in this database or a local temporary table.',16,10);
END;
---Build-
GO
