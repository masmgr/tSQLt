IF OBJECT_ID('tSQLt.AssertEqualsStringExact') IS NOT NULL DROP PROCEDURE tSQLt.AssertEqualsStringExact;
GO
---Build+
CREATE PROCEDURE tSQLt.AssertEqualsStringExact
    @Expected NVARCHAR(MAX),
    @Actual NVARCHAR(MAX),
    @Message NVARCHAR(MAX) = ''
AS
BEGIN
  DECLARE @IsEqual BIT, @FirstDifference BIGINT;
  SELECT @IsEqual = IsEqual, @FirstDifference = FirstDifference
    FROM tSQLt.Private_CompareStringExact(@Expected, @Actual);
  IF @IsEqual = 1 RETURN 0;

  DECLARE @Start BIGINT, @ExpectedHex NVARCHAR(MAX), @ActualHex NVARCHAR(MAX), @Msg NVARCHAR(MAX);
  -- At most four code units before and four after the first difference.
  SET @Start = CASE WHEN @FirstDifference > 4 THEN (@FirstDifference - 5) * 2 + 1 ELSE 1 END;
  SELECT @ExpectedHex = CASE WHEN @Expected IS NULL THEN N'NULL' ELSE
           COALESCE(CONVERT(NVARCHAR(MAX), master.dbo.fn_varbintohexstr(SUBSTRING(CONVERT(VARBINARY(MAX), @Expected), @Start, 18))), N'0x') END,
         @ActualHex = CASE WHEN @Actual IS NULL THEN N'NULL' ELSE
           COALESCE(CONVERT(NVARCHAR(MAX), master.dbo.fn_varbintohexstr(SUBSTRING(CONVERT(VARBINARY(MAX), @Actual), @Start, 18))), N'0x') END;
  SET @Msg = NCHAR(13)+NCHAR(10)
      + N'Expected: ' + tSQLt.Private_FormatStringExact(@Expected)
      + N' (bytes: ' + COALESCE(CONVERT(NVARCHAR(MAX), DATALENGTH(@Expected)), N'NULL') + N')'
      + NCHAR(13)+NCHAR(10)
      + N'but was : ' + tSQLt.Private_FormatStringExact(@Actual)
      + N' (bytes: ' + COALESCE(CONVERT(NVARCHAR(MAX), DATALENGTH(@Actual)), N'NULL') + N')'
      + NCHAR(13)+NCHAR(10)
      + N'First difference (UTF-16 code unit, 1-based): ' + CONVERT(NVARCHAR(MAX), @FirstDifference)
      + NCHAR(13)+NCHAR(10)
      + N'Hex context (starting at byte ' + CONVERT(NVARCHAR(MAX), @Start) + N'): expected '
      + @ExpectedHex + N'; actual ' + @ActualHex;
  EXEC tSQLt.Fail @Message, @Msg;
END;
---Build-
GO
