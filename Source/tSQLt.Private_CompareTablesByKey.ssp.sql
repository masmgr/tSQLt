IF OBJECT_ID('tSQLt.Private_CompareTablesByKey') IS NOT NULL DROP PROCEDURE tSQLt.Private_CompareTablesByKey;
GO
---Build+
CREATE PROCEDURE tSQLt.Private_CompareTablesByKey
  @KeyColumns NVARCHAR(MAX),
  @Expected NVARCHAR(MAX),
  @Actual NVARCHAR(MAX),
  @Message NVARCHAR(MAX),
  @ExpectedSnapshot NVARCHAR(MAX),
  @ActualSnapshot NVARCHAR(MAX),
  @ResultTable NVARCHAR(MAX)
AS
BEGIN
  DECLARE @Keys TABLE (Ordinal INT IDENTITY(1,1), Name NVARCHAR(128) COLLATE DATABASE_DEFAULT);
  DECLARE @Columns TABLE (Ordinal INT, Name NVARCHAR(128) COLLATE DATABASE_DEFAULT, TypeId INT);
  INSERT @Columns
    SELECT column_id,name,system_type_id FROM sys.columns
     WHERE object_id = OBJECT_ID(@ExpectedSnapshot);

  -- Parse a list of identifiers, including escaped brackets and quoted commas.
  DECLARE @Pos INT, @Len INT, @Token NVARCHAR(MAX), @Ch NCHAR(1), @Closed BIT;
  SET @Pos = 1;
  SET @Len = LEN(@KeyColumns);
  IF NULLIF(LTRIM(RTRIM(@KeyColumns)),N'') IS NULL GOTO InvalidKeys;
  WHILE @Pos <= @Len
  BEGIN
    WHILE @Pos <= @Len AND SUBSTRING(@KeyColumns,@Pos,1) IN (N' ',NCHAR(9),NCHAR(10),NCHAR(13)) SET @Pos = @Pos+1;
    SET @Token = N'';
    IF SUBSTRING(@KeyColumns,@Pos,1) = N'['
    BEGIN
      SET @Pos = @Pos+1;
      SET @Closed = 0;
      WHILE @Pos <= @Len AND @Closed = 0
      BEGIN
        SET @Ch = SUBSTRING(@KeyColumns,@Pos,1);
        IF @Ch = N']'
        BEGIN
          IF SUBSTRING(@KeyColumns,@Pos+1,1) = N']' SET @Pos = @Pos+1;
          ELSE SET @Closed = 1;
        END;
        IF @Closed = 0 SET @Token = @Token+@Ch;
        SET @Pos = @Pos+1;
      END;
      IF @Closed = 0 GOTO InvalidKeys;
      WHILE @Pos <= @Len AND SUBSTRING(@KeyColumns,@Pos,1) IN (N' ',NCHAR(9),NCHAR(10),NCHAR(13)) SET @Pos = @Pos+1;
      IF @Pos <= @Len AND SUBSTRING(@KeyColumns,@Pos,1) <> N',' GOTO InvalidKeys;
    END
    ELSE
    BEGIN
      WHILE @Pos <= @Len AND SUBSTRING(@KeyColumns,@Pos,1) <> N','
      BEGIN
        SET @Ch = SUBSTRING(@KeyColumns,@Pos,1);
        IF @Ch IN (N'[',N']') GOTO InvalidKeys;
        SET @Token = @Token+@Ch;
        SET @Pos = @Pos+1;
      END;
      WHILE DATALENGTH(@Token)>0 AND RIGHT(@Token,1) IN (N' ',NCHAR(9),NCHAR(10),NCHAR(13))
        SET @Token = LEFT(@Token,DATALENGTH(@Token)/2-1);
    END;
    IF LEN(@Token) = 0 OR DATALENGTH(@Token) > 256 GOTO InvalidKeys;
    IF EXISTS(SELECT 1 FROM @Keys WHERE Name = @Token) GOTO InvalidKeys;
    IF NOT EXISTS(SELECT 1 FROM @Columns WHERE Name = @Token) GOTO InvalidKeys;
    INSERT @Keys(Name) VALUES(@Token);
    IF @Pos = @Len AND SUBSTRING(@KeyColumns,@Pos,1) = N',' GOTO InvalidKeys;
    SET @Pos = @Pos+1;
  END;

  IF EXISTS(SELECT 1 FROM @Columns E WHERE NOT EXISTS
    (SELECT 1 FROM sys.columns A WHERE A.object_id = OBJECT_ID(@ActualSnapshot)
       AND A.name COLLATE DATABASE_DEFAULT = E.Name))
  BEGIN
    RAISERROR('AssertEqualsTableByKey: Actual is missing a column from Expected.',16,10);
    RETURN;
  END;

  DECLARE @List NVARCHAR(MAX), @Join NVARCHAR(MAX), @KeySelect NVARCHAR(MAX), @Order NVARCHAR(MAX), @Aliases NVARCHAR(MAX);
  DECLARE @Cmd NVARCHAR(MAX), @Text NVARCHAR(MAX), @Side INT;
  DECLARE @Projection NVARCHAR(MAX), @NormalizedProjection NVARCHAR(MAX), @Common NVARCHAR(MAX), @DuplicateSelect NVARCHAR(MAX);
  SELECT @List = STUFF((SELECT ','+QUOTENAME(Name) FROM @Columns ORDER BY Ordinal FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,'');
  -- GROUP BY validates the same data-type family as AssertEqualsTable, even on empty inputs.
  BEGIN TRY
    IF EXISTS(SELECT 1 FROM @Columns WHERE TypeId = 189) RAISERROR('Unsupported timestamp.',16,10);
    SET @Cmd = N'DECLARE @N INT; SELECT @N=COUNT(*) FROM '+@ExpectedSnapshot+N' GROUP BY '+@List+
      N'; SELECT @N=COUNT(*) FROM '+@ActualSnapshot+N' GROUP BY '+@List+N';';
    EXEC(@Cmd);
  END TRY
  BEGIN CATCH
    RAISERROR('The table contains a datatype that is not supported for tSQLt.AssertEqualsTableByKey.',16,10);
    RETURN;
  END CATCH;

  -- UNION ALL selects a common SQL type before key uniqueness and value comparison.
  -- This also detects keys such as varchar '01' and '1' that become equal to int 1.
  SELECT @Projection = (SELECT N','+QUOTENAME(Name)+N' AS '+QUOTENAME(N'C'+CAST(Ordinal AS NVARCHAR(10))) FROM @Columns ORDER BY Ordinal FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),
    @NormalizedProjection = (SELECT N',C'+CAST(Ordinal AS NVARCHAR(10)) FROM @Columns ORDER BY Ordinal FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)');
  SET @Common = N';WITH Normalized AS (SELECT 0 Side'+@Projection+N' FROM '+@ExpectedSnapshot+N' UNION ALL SELECT 1'+@Projection+N' FROM '+@ActualSnapshot+N')';
  -- Values are compared after UNION ALL type conversion, so format them by that common type,
  -- not by the Expected type (an int Expected column must not render a float Actual as int).
  SET @Cmd = @Common+N' SELECT TOP(0) * INTO '+@ResultTable+N' FROM Normalized;';
  EXEC(@Cmd);
  UPDATE C SET TypeId = S.system_type_id
    FROM @Columns C
    JOIN sys.columns S ON S.object_id = OBJECT_ID(@ResultTable)
     AND S.name COLLATE DATABASE_DEFAULT = N'C'+CAST(C.Ordinal AS NVARCHAR(10));
  SET @Cmd = N'DROP TABLE '+@ResultTable+N';';
  EXEC(@Cmd);
  SELECT @List = STUFF((SELECT N',C'+CAST(C.Ordinal AS NVARCHAR(10)) FROM @Keys K JOIN @Columns C ON C.Name=K.Name ORDER BY K.Ordinal FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,N''),
    @DuplicateSelect = STUFF((SELECT N',C'+CAST(C.Ordinal AS NVARCHAR(10))+N' AS K'+CAST(K.Ordinal AS NVARCHAR(10)) FROM @Keys K JOIN @Columns C ON C.Name=K.Name ORDER BY K.Ordinal FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,N'');
  -- Positional internal names allow keys named DifferenceType, ColumnName, etc.
  SELECT @Order = (SELECT QUOTENAME(N'K'+CAST(Ordinal AS NVARCHAR(10)))+N',' FROM @Keys ORDER BY Ordinal FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),
    @Aliases = (SELECT QUOTENAME(LEFT(N'Key'+CAST(Ordinal AS NVARCHAR(10))+N': '+Name,128))+N',' FROM @Keys ORDER BY Ordinal FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)');
  SET @Side = 0;
  WHILE @Side < 2
  BEGIN
    SET @Cmd = @Common+N' SELECT '+@DuplicateSelect+N',COUNT_BIG(*) AS [DuplicateCount] INTO '+@ResultTable+N' FROM Normalized WHERE Side='+CAST(@Side AS NVARCHAR(1))+
      N' GROUP BY '+@List+N' HAVING COUNT_BIG(*)>1;
      EXEC tSQLt.Private_MarktSQLtTempObject @ObjectName=@Result,@ObjectType=N''TABLE'';
      SELECT @Groups=COUNT_BIG(*) FROM '+@ResultTable+N';
      IF @Groups > 0
        EXEC tSQLt.TableToText @txt=@Text OUTPUT,@TableName=@Result,@OrderBy=@Ordering,@PrintOnlyColumnNameAliasList=@Aliases;
      DROP TABLE '+@ResultTable+N';';
    SET @Text = NULL;
    DECLARE @DuplicateAliases NVARCHAR(MAX), @DuplicateOrder NVARCHAR(MAX), @Groups BIGINT, @Note NVARCHAR(200), @Length INT, @LastLine INT;
    SET @DuplicateAliases=@Aliases+N'[DuplicateCount]';
    SET @DuplicateOrder=@Order+N'DuplicateCount';
    EXEC sys.sp_executesql @Cmd,N'@Text NVARCHAR(MAX) OUTPUT,@Groups BIGINT OUTPUT,@Ordering NVARCHAR(MAX),@Aliases NVARCHAR(MAX),@Result NVARCHAR(MAX)',@Text OUTPUT,@Groups OUTPUT,@DuplicateOrder,@DuplicateAliases,@ResultTable;
    IF @Text IS NOT NULL
    BEGIN
      SET @Text = N'AssertEqualsTableByKey: duplicate keys in '+CASE @Side WHEN 0 THEN @Expected ELSE @Actual END+N'.'+CHAR(13)+CHAR(10)+@Text;
      -- RAISERROR keeps at most 2047 characters. Cut at a row boundary and say so,
      -- instead of letting the table be cut off mid-row without notice.
      IF DATALENGTH(@Text)/2 > 2047
      BEGIN
        SET @Note = CHAR(13)+CHAR(10)+N'... (output truncated; '+CAST(@Groups AS NVARCHAR(20))+N' duplicate keys in total)';
        SET @Text = LEFT(@Text,2047-DATALENGTH(@Note)/2);
        SET @Length = DATALENGTH(@Text)/2;
        SET @LastLine = CHARINDEX(NCHAR(10),REVERSE(@Text));
        IF @LastLine > 0 SET @Text = LEFT(@Text,@Length-@LastLine-1);
        SET @Text = @Text+@Note;
      END;
      RAISERROR('%s',16,10,@Text);
      RETURN;
    END;
    SET @Side = @Side+1;
  END;

  -- Rename all source columns by ordinal to keep the existence marker collision-free.
  DECLARE @Name NVARCHAR(128), @Ordinal INT;
  SELECT @Join = STUFF((SELECT N' AND (E.C'+CAST(C.Ordinal AS NVARCHAR(10))+N'=A.C'+CAST(C.Ordinal AS NVARCHAR(10))+N' OR (E.C'+CAST(C.Ordinal AS NVARCHAR(10))+N' IS NULL AND A.C'+CAST(C.Ordinal AS NVARCHAR(10))+N' IS NULL))' FROM @Keys K JOIN @Columns C ON C.Name=K.Name ORDER BY K.Ordinal FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,5,N''),
    @KeySelect = (SELECT N',CASE WHEN E.[Present] IS NULL THEN A.C'+CAST(C.Ordinal AS NVARCHAR(10))+N' ELSE E.C'+CAST(C.Ordinal AS NVARCHAR(10))+N' END AS K'+CAST(K.Ordinal AS NVARCHAR(10)) FROM @Keys K JOIN @Columns C ON C.Name=K.Name ORDER BY K.Ordinal FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)');

  DECLARE @Values NVARCHAR(MAX), @TypeId INT, @Expr NVARCHAR(MAX), @EValue NVARCHAR(MAX), @AValue NVARCHAR(MAX);
  SET @Values = N'SELECT CAST(NULL AS NVARCHAR(128)) ColumnName,CAST(NULL AS NVARCHAR(MAX)) ExpectedValue,CAST(NULL AS NVARCHAR(MAX)) ActualValue WHERE 1=0';
  DECLARE Cols CURSOR LOCAL FAST_FORWARD FOR SELECT Ordinal,Name,TypeId FROM @Columns WHERE Name NOT IN (SELECT Name FROM @Keys) ORDER BY Ordinal;
  OPEN Cols;
  FETCH NEXT FROM Cols INTO @Ordinal,@Name,@TypeId;
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SET @Expr = N'CONVERT(NVARCHAR(MAX),{alias}.C'+CAST(@Ordinal AS NVARCHAR(10))+
      CASE WHEN @TypeId IN (165,173) THEN N',1)' WHEN @TypeId IN (59,60,62,122) THEN N',2)' WHEN @TypeId IN (58,61) THEN N',121)' ELSE N')' END;
    SET @EValue = REPLACE(@Expr,N'{alias}',N'E');
    SET @AValue = REPLACE(@Expr,N'{alias}',N'A');
    SET @Values = @Values+N' UNION ALL SELECT N'''+REPLACE(@Name,'''','''''')+N''','+@EValue+N','+@AValue+
      N' WHERE E.[Present]=1 AND A.[Present]=1 AND EXISTS(SELECT E.C'+CAST(@Ordinal AS NVARCHAR(10))+N' EXCEPT SELECT A.C'+CAST(@Ordinal AS NVARCHAR(10))+N')';
    FETCH NEXT FROM Cols INTO @Ordinal,@Name,@TypeId;
  END;
  CLOSE Cols;
  DEALLOCATE Cols;
  SET @Cmd = @Common+N', E AS (SELECT 1 [Present]'+@NormalizedProjection+N' FROM Normalized WHERE Side=0),
    A AS (SELECT 1 [Present]'+@NormalizedProjection+N' FROM Normalized WHERE Side=1)
    SELECT '+STUFF(@KeySelect,1,1,N'')+N',
      CASE WHEN E.[Present] IS NULL THEN N''Extra'' WHEN A.[Present] IS NULL THEN N''Missing'' ELSE N''Changed'' END D,
      V.ColumnName,V.ExpectedValue,V.ActualValue
    INTO '+@ResultTable+N' FROM E FULL OUTER JOIN A ON '+@Join+N'
    CROSS APPLY ('+@Values+N' UNION ALL
      SELECT NULL,CASE WHEN E.[Present] IS NULL THEN N''<missing>'' ELSE N''<present>'' END,
      CASE WHEN A.[Present] IS NULL THEN N''<missing>'' ELSE N''<present>'' END
      WHERE E.[Present] IS NULL OR A.[Present] IS NULL) V;
    EXEC tSQLt.Private_MarktSQLtTempObject @ObjectName=@Result,@ObjectType=N''TABLE'';
    IF EXISTS(SELECT 1 FROM '+@ResultTable+N')
    BEGIN
      EXEC tSQLt.TableToText @txt=@Text OUTPUT,@TableName=@Result,@OrderBy=@Ordering,@PrintOnlyColumnNameAliasList=@Aliases;
    END;';
  -- Sort changed columns by their source ordinal without displaying that ordinal.
  -- TableToText aliases are positional; key prefixes keep all headers distinct.
  SET @Order = @Order+N'D,CASE ColumnName'+
    (SELECT N' WHEN N'''+REPLACE(Name,'''','''''')+N''' THEN '+CAST(Ordinal AS NVARCHAR(10)) FROM @Columns ORDER BY Ordinal FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)')+N' ELSE 0 END';
  SET @Aliases = @Aliases+N'[DifferenceType],[ColumnName],[ExpectedValue],[ActualValue]';
  SET @Text = NULL;
  EXEC sys.sp_executesql @Cmd,N'@Text NVARCHAR(MAX) OUTPUT,@Ordering NVARCHAR(MAX),@Aliases NVARCHAR(MAX),@Result NVARCHAR(MAX)',@Text OUTPUT,@Order,@Aliases,@ResultTable;
  IF @Text IS NOT NULL
  BEGIN
    SET @Text = ISNULL(@Message+CHAR(13)+CHAR(10),N'')+N'Unexpected/missing resultset rows or changed column values!'+CHAR(13)+CHAR(10)+@Text;
    EXEC tSQLt.Fail @Text;
  END;
  RETURN;
InvalidKeys:
  RAISERROR('AssertEqualsTableByKey: @KeyColumns must be a nonempty list of distinct column names present in Expected. Use brackets to quote identifiers.',16,10);
END;
---Build-
GO
