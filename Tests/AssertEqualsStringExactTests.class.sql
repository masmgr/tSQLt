EXEC tSQLt.NewTestClass 'AssertEqualsStringExactTests';
GO
CREATE PROCEDURE AssertEqualsStringExactTests.[test equal values return zero including NULL empty and long Unicode]
AS
BEGIN
  DECLARE @Result INT, @Value NVARCHAR(MAX);
  SET @Value = REPLICATE(CAST(NCHAR(12354) AS NVARCHAR(MAX)), 10000) + N'  ';
  EXEC @Result = tSQLt.AssertEqualsStringExact @Value, @Value;
  EXEC tSQLt.AssertEquals 0, @Result;
  EXEC tSQLt.AssertEqualsStringExact NULL, NULL;
  EXEC tSQLt.AssertEqualsStringExact N'', N'';
  EXEC tSQLt.AssertEqualsStringExact N' ', N' ';
END;
GO
CREATE PROCEDURE AssertEqualsStringExactTests.[test public assertion rejects case whitespace controls and NULL differences]
AS
BEGIN
  EXEC tSQLt_testutil.assertFailCalled N'EXEC tSQLt.AssertEqualsStringExact N''a'', N''A'';';
  EXEC tSQLt_testutil.assertFailCalled N'EXEC tSQLt.AssertEqualsStringExact N''a'', N''a '';';
  EXEC tSQLt_testutil.assertFailCalled N'EXEC tSQLt.AssertEqualsStringExact N''a '', N''a'';';
  EXEC tSQLt_testutil.assertFailCalled N'EXEC tSQLt.AssertEqualsStringExact N'''', N'' '';';
  EXEC tSQLt_testutil.assertFailCalled N'EXEC tSQLt.AssertEqualsStringExact NULL, N'''';';
  EXEC tSQLt_testutil.assertFailCalled N'EXEC tSQLt.AssertEqualsStringExact N'''', NULL;';
  EXEC tSQLt_testutil.assertFailCalled N'DECLARE @v NVARCHAR(MAX); SET @v = NCHAR(12288); EXEC tSQLt.AssertEqualsStringExact N'' '', @v;';
  EXEC tSQLt_testutil.assertFailCalled N'DECLARE @v NVARCHAR(MAX), @lf NVARCHAR(MAX); SET @v = NCHAR(13)+NCHAR(10); SET @lf = NCHAR(10); EXEC tSQLt.AssertEqualsStringExact @lf, @v;';
END;
GO
CREATE PROCEDURE AssertEqualsStringExactTests.[test comparison reports first differing unit and prefix boundary]
AS
BEGIN
  DECLARE @Position BIGINT;
  SELECT @Position = FirstDifference FROM tSQLt.Private_CompareStringExact(N'abcXdef', N'abcYdef');
  EXEC tSQLt.AssertEquals 4, @Position;
  SELECT @Position = FirstDifference FROM tSQLt.Private_CompareStringExact(N'abc', N'abc ');
  EXEC tSQLt.AssertEquals 4, @Position;
  SELECT @Position = FirstDifference FROM tSQLt.Private_CompareStringExact(N'', N'a');
  EXEC tSQLt.AssertEquals 1, @Position;
  SELECT @Position = FirstDifference FROM tSQLt.Private_CompareStringExact(N'a', N'');
  EXEC tSQLt.AssertEquals 1, @Position;
END;
GO
CREATE PROCEDURE AssertEqualsStringExactTests.[test comparison distinguishes null padding and high byte differences]
AS
BEGIN
  DECLARE @Expected NVARCHAR(MAX), @Actual NVARCHAR(MAX), @Equal BIT, @Position BIGINT;
  SELECT @Expected = CONVERT(NVARCHAR(MAX), 0x61000000), @Actual = N'a';
  SELECT @Equal = IsEqual, @Position = FirstDifference FROM tSQLt.Private_CompareStringExact(@Expected, @Actual);
  EXEC tSQLt.AssertEquals 0, @Equal;
  EXEC tSQLt.AssertEquals 2, @Position;
  SELECT @Expected = CONVERT(NVARCHAR(MAX), 0x0001), @Actual = CONVERT(NVARCHAR(MAX), 0x0002);
  SELECT @Equal = IsEqual, @Position = FirstDifference FROM tSQLt.Private_CompareStringExact(@Expected, @Actual);
  EXEC tSQLt.AssertEquals 0, @Equal;
  EXEC tSQLt.AssertEquals 1, @Position;
END;
GO
CREATE PROCEDURE AssertEqualsStringExactTests.[test comparison does not normalize Unicode or use linguistic equality]
AS
BEGIN
  DECLARE @Equal BIT, @Expected NVARCHAR(MAX), @Actual NVARCHAR(MAX);
  SELECT @Expected = NCHAR(233), @Actual = N'e' + NCHAR(769);
  SELECT @Equal = IsEqual FROM tSQLt.Private_CompareStringExact(@Expected, @Actual);
  EXEC tSQLt.AssertEquals 0, @Equal;
  SELECT @Expected = NCHAR(65313), @Actual = N'A';
  SELECT @Equal = IsEqual FROM tSQLt.Private_CompareStringExact(@Expected, @Actual);
  EXEC tSQLt.AssertEquals 0, @Equal;
END;
GO
CREATE PROCEDURE AssertEqualsStringExactTests.[test comparison counts surrogate pairs as two units]
AS
BEGIN
  DECLARE @Expected NVARCHAR(MAX), @Actual NVARCHAR(MAX), @Position BIGINT;
  SELECT @Expected = CONVERT(NVARCHAR(MAX), 0x3DD800DE4100),
         @Actual = CONVERT(NVARCHAR(MAX), 0x3DD800DE4200);
  SELECT @Position = FirstDifference FROM tSQLt.Private_CompareStringExact(@Expected, @Actual);
  EXEC tSQLt.AssertEquals 3, @Position;
  SELECT @Actual = CONVERT(NVARCHAR(MAX), 0x3DD801DE4100);
  SELECT @Position = FirstDifference FROM tSQLt.Private_CompareStringExact(@Expected, @Actual);
  EXEC tSQLt.AssertEquals 2, @Position;
END;
GO
CREATE PROCEDURE AssertEqualsStringExactTests.[test formatter escapes spaces controls quotes backslashes and non ASCII]
AS
BEGIN
  DECLARE @Value NVARCHAR(MAX), @Formatted NVARCHAR(MAX);
  SET @Value = CONVERT(NVARCHAR(MAX), 0x0000) + N' ' + NCHAR(9) + NCHAR(13) + NCHAR(10)
             + N'"\' + NCHAR(127) + NCHAR(160) + NCHAR(12288) + CONVERT(NVARCHAR(MAX), 0x3DD800DE);
  SET @Formatted = tSQLt.Private_FormatStringExact(@Value);
  EXEC tSQLt.AssertEqualsString N'"\u0000\u0020\t\r\n\"\\\u007F\u00A0\u3000\uD83D\uDE00"', @Formatted;
  SET @Formatted = tSQLt.Private_FormatStringExact(NULL);
  EXEC tSQLt.AssertEqualsString N'NULL', @Formatted;
  SET @Formatted = tSQLt.Private_FormatStringExact(N'');
  EXEC tSQLt.AssertEqualsString N'""', @Formatted;
END;
GO
CREATE PROCEDURE AssertEqualsStringExactTests.[test diagnostic includes custom message lengths position and little endian hex]
AS
BEGIN
  DECLARE @ExpectedMessage NVARCHAR(MAX);
  SET @ExpectedMessage = N'context' + NCHAR(13)+NCHAR(10)
    + N'Expected: "a\u0020" (bytes: 4)' + NCHAR(13)+NCHAR(10)
    + N'but was : "a" (bytes: 2)' + NCHAR(13)+NCHAR(10)
    + N'First difference (UTF-16 code unit, 1-based): 2' + NCHAR(13)+NCHAR(10)
    + N'Hex context (starting at byte 1): expected 0x61002000; actual 0x6100';
  EXEC tSQLt_testutil.AssertFailMessageEquals
    N'EXEC tSQLt.AssertEqualsStringExact N''a '', N''a'', N''context'';', @ExpectedMessage;
END;
GO
CREATE PROCEDURE AssertEqualsStringExactTests.[test NULL diagnostic is distinct from empty in either direction]
AS
BEGIN
  DECLARE @Message NVARCHAR(MAX);
  EXEC tSQLt_testutil.CaptureFailMessage N'EXEC tSQLt.AssertEqualsStringExact NULL, N'''';', @Message OUTPUT;
  EXEC tSQLt.AssertLike N'%Expected: NULL (bytes: NULL)%but was : "" (bytes: 0)%1-based): 1%expected NULL; actual 0x', @Message;
  EXEC tSQLt_testutil.CaptureFailMessage N'EXEC tSQLt.AssertEqualsStringExact N'''', NULL;', @Message OUTPUT;
  EXEC tSQLt.AssertLike N'%Expected: "" (bytes: 0)%but was : NULL (bytes: NULL)%expected 0x; actual NULL', @Message;
END;
GO
CREATE PROCEDURE AssertEqualsStringExactTests.[test long differences beyond display limit and 8000 bytes are compared and shown in hex]
AS
BEGIN
  DECLARE @Message NVARCHAR(MAX);
  EXEC tSQLt_testutil.CaptureFailMessage
    N'DECLARE @e NVARCHAR(MAX), @a NVARCHAR(MAX); SET @e = REPLICATE(CAST(N''x'' AS NVARCHAR(MAX)),10000); SET @a = @e + N''B''; SET @e = @e + N''A''; EXEC tSQLt.AssertEqualsStringExact @e, @a;',
    @Message OUTPUT;
  EXEC tSQLt.AssertLike N'%"... (truncated) (bytes: 20002)%1-based): 10001%starting at byte 19993): expected 0x78007800780078004100; actual 0x78007800780078004200', @Message;
  DECLARE @Length BIGINT; SET @Length = DATALENGTH(@Message);
  IF @Length > 4000 EXEC tSQLt.Fail N'Diagnostic was not bounded.';
END;
GO
CREATE PROCEDURE AssertEqualsStringExactTests.[test formatter truncates only after 128 code units]
AS
BEGIN
  DECLARE @Value NVARCHAR(MAX), @Formatted NVARCHAR(MAX), @Expected NVARCHAR(MAX);
  SET @Value = REPLICATE(CAST(N'x' AS NVARCHAR(MAX)), 128);
  SET @Expected = N'"' + @Value + N'"';
  SET @Formatted = tSQLt.Private_FormatStringExact(@Value);
  EXEC tSQLt.AssertEqualsString @Expected, @Formatted;
  SET @Value = @Value + N'y';
  SET @Expected = @Expected + N'... (truncated)';
  SET @Formatted = tSQLt.Private_FormatStringExact(@Value);
  EXEC tSQLt.AssertEqualsString @Expected, @Formatted;
END;
GO
