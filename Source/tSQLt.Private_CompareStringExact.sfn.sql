IF OBJECT_ID('tSQLt.Private_CompareStringExact') IS NOT NULL DROP FUNCTION tSQLt.Private_CompareStringExact;
GO
---Build+
CREATE FUNCTION tSQLt.Private_CompareStringExact(@Expected NVARCHAR(MAX), @Actual NVARCHAR(MAX))
RETURNS @Comparison TABLE(IsEqual BIT, FirstDifference BIGINT)
AS
BEGIN
  IF @Expected IS NULL OR @Actual IS NULL
  BEGIN
    INSERT INTO @Comparison
      SELECT CASE WHEN @Expected IS NULL AND @Actual IS NULL THEN 1 ELSE 0 END,
             CASE WHEN @Expected IS NULL AND @Actual IS NULL THEN NULL ELSE 1 END;
    RETURN;
  END;

  DECLARE @ExpectedBytes VARBINARY(MAX), @ActualBytes VARBINARY(MAX);
  SELECT @ExpectedBytes = CONVERT(VARBINARY(MAX), @Expected),
         @ActualBytes = CONVERT(VARBINARY(MAX), @Actual);
  IF DATALENGTH(@ExpectedBytes) = DATALENGTH(@ActualBytes) AND @ExpectedBytes = @ActualBytes
  BEGIN
    INSERT INTO @Comparison VALUES(1, NULL);
    RETURN;
  END;

  -- Find the longest common prefix in UTF-16 code units, independent of collation.
  DECLARE @Low BIGINT, @High BIGINT, @Middle BIGINT;
  SELECT @Low = 0,
         @High = CASE WHEN DATALENGTH(@ExpectedBytes) < DATALENGTH(@ActualBytes)
                      THEN DATALENGTH(@ExpectedBytes) ELSE DATALENGTH(@ActualBytes) END / 2;
  WHILE @Low < @High
  BEGIN
    SET @Middle = @Low + (@High - @Low + 1) / 2;
    IF SUBSTRING(@ExpectedBytes, 1, @Middle * 2) = SUBSTRING(@ActualBytes, 1, @Middle * 2)
      SET @Low = @Middle;
    ELSE
      SET @High = @Middle - 1;
  END;
  INSERT INTO @Comparison VALUES(0, @Low + 1);
  RETURN;
END;
---Build-
GO
