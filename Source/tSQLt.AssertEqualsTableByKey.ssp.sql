IF OBJECT_ID('tSQLt.AssertEqualsTableByKey') IS NOT NULL DROP PROCEDURE tSQLt.AssertEqualsTableByKey;
GO
---Build+
CREATE PROCEDURE tSQLt.AssertEqualsTableByKey
  @Expected NVARCHAR(MAX),
  @Actual NVARCHAR(MAX),
  @KeyColumns NVARCHAR(MAX),
  @Message NVARCHAR(MAX) = NULL
AS
BEGIN
  EXEC tSQLt.AssertObjectExists @Expected;
  EXEC tSQLt.AssertObjectExists @Actual;

  -- Resolve object names before quoting them; never execute a supplied SQL fragment.
  DECLARE @E NVARCHAR(MAX), @A NVARCHAR(MAX), @Id INT, @Side INT;
  DECLARE @Name NVARCHAR(MAX), @Quoted NVARCHAR(MAX);
  SET @Side = 0;
  WHILE @Side < 2
  BEGIN
    SET @Name = CASE @Side WHEN 0 THEN @Expected ELSE @Actual END;
    IF PARSENAME(@Name,3) IS NOT NULL OR PARSENAME(@Name,4) IS NOT NULL
    BEGIN
      RAISERROR('AssertEqualsTableByKey requires tables in the current database or local temporary tables.',16,10);
      RETURN;
    END;
    IF @Name LIKE '#%'
      SET @Quoted = QUOTENAME(@Name);
    ELSE
    BEGIN
      SET @Id = OBJECT_ID(@Name);
      SET @Quoted = QUOTENAME(OBJECT_SCHEMA_NAME(@Id))+'.'+QUOTENAME(OBJECT_NAME(@Id));
    END;
    IF @Side = 0 SET @E = @Quoted ELSE SET @A = @Quoted;
    SET @Side = @Side + 1;
  END;

  -- Keep snapshots in the current database: tempdb cannot store database-scoped CLR types.
  DECLARE @Cmd NVARCHAR(MAX), @ESnapshot NVARCHAR(MAX), @ASnapshot NVARCHAR(MAX), @Result NVARCHAR(MAX);
  SELECT @ESnapshot=N'tSQLt.'+QUOTENAME(tSQLt.Private::CreateUniqueObjectName()),
         @ASnapshot=N'tSQLt.'+QUOTENAME(tSQLt.Private::CreateUniqueObjectName()),
         @Result=N'tSQLt.'+QUOTENAME(tSQLt.Private::CreateUniqueObjectName());
  BEGIN TRY
    SET @Cmd=N'SELECT * INTO '+@ESnapshot+N' FROM '+@E+N'; SELECT * INTO '+@ASnapshot+N' FROM '+@A+N';';
    EXEC(@Cmd);
    EXEC tSQLt.Private_MarktSQLtTempObject @ObjectName=@ESnapshot,@ObjectType=N'TABLE';
    EXEC tSQLt.Private_MarktSQLtTempObject @ObjectName=@ASnapshot,@ObjectType=N'TABLE';
    EXEC tSQLt.Private_CompareTablesByKey @KeyColumns,@Expected,@Actual,@Message,@ESnapshot,@ASnapshot,@Result;
  END TRY
  BEGIN CATCH
    DECLARE @Error NVARCHAR(MAX),@Severity INT,@State INT;
    SELECT @Error=ERROR_MESSAGE(),@Severity=ERROR_SEVERITY(),@State=ERROR_STATE();
    -- RAISERROR cannot re-raise a system error number, and THROW is unavailable on
    -- SQL Server 2005/2008, so keep the original number in the message instead.
    -- User errors (50000) such as tSQLt.Failure keep their message unchanged.
    IF ERROR_NUMBER()<>50000
      SET @Error=N'Msg '+CAST(ERROR_NUMBER() AS NVARCHAR(10))+N': '+@Error;
    IF XACT_STATE()<>-1
    BEGIN
      SET @Cmd=N'IF OBJECT_ID(@E) IS NOT NULL DROP TABLE '+@ESnapshot+N';
        IF OBJECT_ID(@A) IS NOT NULL DROP TABLE '+@ASnapshot+N';
        IF OBJECT_ID(@R) IS NOT NULL DROP TABLE '+@Result+N';';
      EXEC sys.sp_executesql @Cmd,N'@E NVARCHAR(MAX),@A NVARCHAR(MAX),@R NVARCHAR(MAX)',@ESnapshot,@ASnapshot,@Result;
    END;
    RAISERROR('%s',@Severity,@State,@Error);
    RETURN;
  END CATCH;
  SET @Cmd=N'DROP TABLE '+@ESnapshot+N'; DROP TABLE '+@ASnapshot+N'; DROP TABLE '+@Result+N';';
  EXEC(@Cmd);
END;
---Build-
GO
