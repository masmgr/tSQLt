IF OBJECT_ID('tSQLt.AssertTableCases') IS NOT NULL DROP PROCEDURE tSQLt.AssertTableCases;
GO
---Build+
CREATE PROCEDURE tSQLt.AssertTableCases
  @TableName NVARCHAR(MAX),
  @CaseIdColumn NVARCHAR(MAX),
  @ExpectedColumn NVARCHAR(MAX),
  @ActualColumn NVARCHAR(MAX),
  @Message NVARCHAR(MAX)=NULL,
  @ExactStrings BIT=0
AS
BEGIN
  DECLARE @ResultTable NVARCHAR(MAX)=N'tSQLt.'+QUOTENAME(tSQLt.Private::CreateUniqueObjectName()),
    @Sql NVARCHAR(MAX), @Text NVARCHAR(MAX), @Total BIGINT=0, @Shown INT=0;
  BEGIN TRY
    SET @Sql=N'CREATE TABLE '+@ResultTable+N'(CaseId NVARCHAR(128),IsEqual BIT,
      ExpectedValue NVARCHAR(MAX),ActualValue NVARCHAR(MAX),Inputs NVARCHAR(MAX));';
    EXEC(@Sql);
    EXEC tSQLt.Private_MarktSQLtTempObject @ObjectName=@ResultTable,@ObjectType=N'TABLE';
    EXEC tSQLt.Private_CompareTableCases @TableName,@CaseIdColumn,@ExpectedColumn,@ActualColumn,@ExactStrings,@ResultTable;
    SET @Sql=N'SELECT @Total=COUNT_BIG(*) FROM '+@ResultTable+N' WHERE IsEqual=0;
      DECLARE @Line NVARCHAR(MAX);
      DECLARE RowsToDisplay CURSOR LOCAL FAST_FORWARD FOR
        SELECT tSQLt.Private_FormatStringExact(CaseId)+N'' | ''+
          tSQLt.Private_FormatStringExact(ExpectedValue)+N'' | ''+
          tSQLt.Private_FormatStringExact(ActualValue)+N'' | ''+LEFT(Inputs,2048)
          FROM '+@ResultTable+N' WHERE IsEqual=0 ORDER BY CONVERT(VARBINARY(256),CaseId),DATALENGTH(CaseId);
      SET @Text=N''CaseId | Expected | Actual | Inputs'';
      OPEN RowsToDisplay;
      FETCH NEXT FROM RowsToDisplay INTO @Line;
      WHILE @@FETCH_STATUS=0 AND @Shown<20
      BEGIN
        IF DATALENGTH(@Text+NCHAR(13)+NCHAR(10)+@Line)>31000 BREAK;
        SET @Text=@Text+NCHAR(13)+NCHAR(10)+@Line;
        SET @Shown=@Shown+1;
        FETCH NEXT FROM RowsToDisplay INTO @Line;
      END;
      CLOSE RowsToDisplay;
      DEALLOCATE RowsToDisplay;';
    EXEC sys.sp_executesql @Sql,N'@Total BIGINT OUTPUT,@Shown INT OUTPUT,@Text NVARCHAR(MAX) OUTPUT',
      @Total OUTPUT,@Shown OUTPUT,@Text OUTPUT;
    SET @Sql=N'DROP TABLE '+@ResultTable;
    EXEC(@Sql);
  END TRY
  BEGIN CATCH
    DECLARE @Error NVARCHAR(MAX)=ERROR_MESSAGE(),@Severity INT=ERROR_SEVERITY(),@State INT=ERROR_STATE();
    IF XACT_STATE()<>-1
    BEGIN
      SET @Sql=N'IF OBJECT_ID(@Name) IS NOT NULL DROP TABLE '+@ResultTable;
      EXEC sys.sp_executesql @Sql,N'@Name NVARCHAR(MAX)',@ResultTable;
    END;
    RAISERROR('%s',@Severity,@State,@Error);
    RETURN;
  END CATCH;
  IF @Total>0
  BEGIN
    SET @Text=N'Mismatches: '+CONVERT(NVARCHAR(20),@Total)+N'; displayed: '+CONVERT(NVARCHAR(20),@Shown)
      +CASE WHEN @Shown<@Total THEN N' (truncated)' ELSE N'' END+NCHAR(13)+NCHAR(10)+@Text;
    DECLARE @Prefix NVARCHAR(MAX)=CASE WHEN @Message IS NULL THEN N'' ELSE @Message+NCHAR(13)+NCHAR(10) END;
    EXEC tSQLt.Fail @Prefix,@Text;
  END;
END;
---Build-
GO
