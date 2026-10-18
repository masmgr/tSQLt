IF OBJECT_ID('tSQLt.Private_FormatStringExact') IS NOT NULL DROP FUNCTION tSQLt.Private_FormatStringExact;
GO
---Build+
CREATE FUNCTION tSQLt.Private_FormatStringExact(@Value NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
  IF @Value IS NULL RETURN N'NULL';

  DECLARE @Bytes VARBINARY(MAX), @Result NVARCHAR(MAX), @Position INT,
          @Unit INT, @Count BIGINT, @Hex NCHAR(16);
  SELECT @Bytes = CONVERT(VARBINARY(MAX), @Value), @Result = N'"', @Position = 1,
         @Count = DATALENGTH(@Value) / 2, @Hex = N'0123456789ABCDEF';
  -- Bound diagnostic work and output; comparison never uses this abbreviated value.
  WHILE @Position <= @Count AND @Position <= 128
  BEGIN
    SET @Unit = CONVERT(INT, SUBSTRING(@Bytes, @Position * 2 - 1, 1))
              + 256 * CONVERT(INT, SUBSTRING(@Bytes, @Position * 2, 1));
    SET @Result = @Result + CASE
      WHEN @Unit = 9 THEN N'\t'
      WHEN @Unit = 10 THEN N'\n'
      WHEN @Unit = 13 THEN N'\r'
      WHEN @Unit = 34 THEN N'\"'
      WHEN @Unit = 92 THEN N'\\'
      WHEN @Unit BETWEEN 33 AND 126 THEN NCHAR(@Unit)
      ELSE N'\u' + SUBSTRING(@Hex, @Unit / 4096 + 1, 1)
                   + SUBSTRING(@Hex, @Unit / 256 % 16 + 1, 1)
                   + SUBSTRING(@Hex, @Unit / 16 % 16 + 1, 1)
                   + SUBSTRING(@Hex, @Unit % 16 + 1, 1) END;
    SET @Position = @Position + 1;
  END;
  RETURN @Result + N'"' + CASE WHEN @Count > 128 THEN N'... (truncated)' ELSE N'' END;
END;
---Build-
GO
