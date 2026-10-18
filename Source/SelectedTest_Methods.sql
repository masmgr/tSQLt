IF OBJECT_ID('tSQLt.RunSelected') IS NOT NULL DROP PROCEDURE tSQLt.RunSelected;
IF OBJECT_ID('tSQLt.ListTests') IS NOT NULL DROP PROCEDURE tSQLt.ListTests;
IF OBJECT_ID('tSQLt.Private_RunSelected') IS NOT NULL DROP PROCEDURE tSQLt.Private_RunSelected;
IF OBJECT_ID('tSQLt.Private_SelectTests') IS NOT NULL DROP PROCEDURE tSQLt.Private_SelectTests;
IF OBJECT_ID('tSQLt.Private_ParseTagAnnotation') IS NOT NULL DROP FUNCTION tSQLt.Private_ParseTagAnnotation;
IF OBJECT_ID('tSQLt.[@tSQLt:Tag]') IS NOT NULL DROP FUNCTION tSQLt.[@tSQLt:Tag];
GO
---Build+
CREATE FUNCTION tSQLt.[@tSQLt:Tag](@Tag NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN SELECT CAST(NULL AS NVARCHAR(MAX)) AS AnnotationCmd;
GO

-- Parse only a single string literal. In particular, never evaluate annotation SQL
-- while discovering tests (including SQL appended after a valid tag literal).
CREATE FUNCTION tSQLt.Private_ParseTagAnnotation(@Annotation NVARCHAR(MAX))
RETURNS @Tags TABLE(Tag NVARCHAR(MAX), IsValid BIT)
AS
BEGIN
  DECLARE @Prefix NVARCHAR(100) = N'tSQLt.[@tSQLt:Tag]';
  DECLARE @Whitespace NVARCHAR(10) = N' '+NCHAR(9)+NCHAR(10)+NCHAR(11)+NCHAR(12)+NCHAR(13);
  IF LEFT(@Annotation,LEN(@Prefix)) <> @Prefix
  BEGIN
    -- A missing closing bracket still belongs to Tag; TagSomethingElse does not.
    IF LEFT(@Annotation,LEN(@Prefix)-1) = LEFT(@Prefix,LEN(@Prefix)-1)
       AND (LEN(@Annotation) = LEN(@Prefix)-1
            OR SUBSTRING(@Annotation,LEN(@Prefix),1) = N'('
            OR CHARINDEX(SUBSTRING(@Annotation,LEN(@Prefix),1),@Whitespace) > 0)
      INSERT INTO @Tags VALUES(NULL,0);
    RETURN;
  END;

  DECLARE @Position INT = LEN(@Prefix)+1;
  DECLARE @Length INT = LEN(@Annotation);
  DECLARE @Tag NVARCHAR(MAX) = N'';
  DECLARE @Closed BIT = 0;
  DECLARE @Valid BIT = 0;

  WHILE @Position <= @Length AND CHARINDEX(SUBSTRING(@Annotation,@Position,1),@Whitespace) > 0
    SET @Position = @Position+1;
  IF SUBSTRING(@Annotation,@Position,1) = N'('
  BEGIN
    SET @Position = @Position+1;
    WHILE @Position <= @Length AND CHARINDEX(SUBSTRING(@Annotation,@Position,1),@Whitespace) > 0
      SET @Position = @Position+1;
    IF SUBSTRING(@Annotation,@Position,1) COLLATE Latin1_General_BIN2 = N'N'
      SET @Position = @Position+1;
    IF SUBSTRING(@Annotation,@Position,1) = N''''
    BEGIN
      SET @Position = @Position+1;
      WHILE @Position <= @Length AND @Closed = 0
      BEGIN
        IF SUBSTRING(@Annotation,@Position,1) = N''''
        BEGIN
          IF SUBSTRING(@Annotation,@Position+1,1) = N''''
          BEGIN
            SET @Tag = @Tag+N'''';
            SET @Position = @Position+2;
          END;
          ELSE
          BEGIN
            SET @Closed = 1;
            SET @Position = @Position+1;
          END;
        END;
        ELSE
        BEGIN
          SET @Tag = @Tag+SUBSTRING(@Annotation,@Position,1);
          SET @Position = @Position+1;
        END;
      END;
      WHILE @Position <= @Length AND CHARINDEX(SUBSTRING(@Annotation,@Position,1),@Whitespace) > 0
        SET @Position = @Position+1;
      IF @Closed = 1 AND SUBSTRING(@Annotation,@Position,1) = N')'
      BEGIN
        SET @Position = @Position+1;
        WHILE @Position <= @Length AND CHARINDEX(SUBSTRING(@Annotation,@Position,1),@Whitespace) > 0
          SET @Position = @Position+1;
        IF @Position > @Length
           AND LEN(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@Tag,NCHAR(9),N''),NCHAR(10),N''),NCHAR(11),N''),NCHAR(12),N''),NCHAR(13),N'')) > 0
          SET @Valid = 1;
      END;
    END;
  END;
  INSERT INTO @Tags VALUES(@Tag,@Valid);
  RETURN;
END;
GO

-- The caller owns #SelectedTests so both public methods consume the same snapshot.
CREATE PROCEDURE tSQLt.Private_SelectTests
  @Tag NVARCHAR(MAX),
  @NamePattern NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;
  IF @Tag IS NOT NULL
     AND LEN(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@Tag,NCHAR(9),N''),NCHAR(10),N''),NCHAR(11),N''),NCHAR(12),N''),NCHAR(13),N'')) = 0
  BEGIN
    RAISERROR('Tag must not be empty or whitespace.',16,10);
    RETURN -1;
  END;

  SELECT T.ObjectId,T.SchemaId,T.TestClassName,T.Name AS TestCaseName,
         QUOTENAME(T.TestClassName)+N'.'+QUOTENAME(T.Name) AS FullName
    INTO #SelectionCandidates
    FROM tSQLt.Tests AS T
   WHERE @NamePattern IS NULL OR T.TestClassName+N'.'+T.Name LIKE @NamePattern;

  IF @Tag IS NULL
  BEGIN
    INSERT INTO #SelectedTests SELECT * FROM #SelectionCandidates;
    RETURN 0;
  END;

  SELECT C.ObjectId,P.Tag,P.IsValid
    INTO #SelectionTags
    FROM #SelectionCandidates AS C
   CROSS APPLY tSQLt.Private_ListTestAnnotations(C.ObjectId) AS A
   CROSS APPLY tSQLt.Private_ParseTagAnnotation(A.Annotation) AS P;

  DECLARE @InvalidTest NVARCHAR(MAX);
  SELECT TOP(1) @InvalidTest = C.FullName
    FROM #SelectionCandidates AS C
    JOIN #SelectionTags AS T ON T.ObjectId = C.ObjectId
   WHERE T.IsValid = 0
   ORDER BY C.TestClassName,C.TestCaseName;
  IF @InvalidTest IS NOT NULL
  BEGIN
    RAISERROR('Invalid Tag annotation on test %s. Expected a single nonempty string literal.',16,10,@InvalidTest);
    RETURN -1;
  END;

  INSERT INTO #SelectedTests
    SELECT C.* FROM #SelectionCandidates AS C
     WHERE EXISTS(SELECT 1 FROM #SelectionTags AS T
                   WHERE T.ObjectId = C.ObjectId AND T.Tag = @Tag
                     AND DATALENGTH(T.Tag) = DATALENGTH(@Tag));
  RETURN 0;
END;
GO

CREATE PROCEDURE tSQLt.ListTests
  @Tag NVARCHAR(MAX) = NULL,
  @NamePattern NVARCHAR(MAX) = NULL
AS
BEGIN
  SET NOCOUNT ON;
  CREATE TABLE #SelectedTests(ObjectId INT,SchemaId INT,TestClassName SYSNAME COLLATE DATABASE_DEFAULT,TestCaseName SYSNAME COLLATE DATABASE_DEFAULT,FullName NVARCHAR(517) COLLATE DATABASE_DEFAULT);
  DECLARE @ReturnCode INT;
  EXEC @ReturnCode = tSQLt.Private_SelectTests @Tag,@NamePattern;
  IF @ReturnCode <> 0 RETURN -1;
  SELECT TestClassName,TestCaseName,FullName FROM #SelectedTests ORDER BY TestClassName,TestCaseName;
  RETURN 0;
END;
GO

CREATE PROCEDURE tSQLt.Private_RunSelected
  @TestResultFormatter NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @FullName NVARCHAR(MAX),@SchemaId INT;
  DECLARE @SetUp NVARCHAR(MAX),@CleanUp NVARCHAR(MAX);
  DECLARE TestCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT FullName,SchemaId FROM #SelectedTests ORDER BY NEWID();
  OPEN TestCursor;
  FETCH NEXT FROM TestCursor INTO @FullName,@SchemaId;
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SELECT @SetUp = NULL,@CleanUp = NULL;
    EXEC tSQLt.Private_GetClassHelperProcedureName @SchemaId,@SetUp OUT,@CleanUp OUT;
    EXEC tSQLt.Private_RunTest @FullName,@SetUp,@CleanUp;
    FETCH NEXT FROM TestCursor INTO @FullName,@SchemaId;
  END;
  CLOSE TestCursor;
  DEALLOCATE TestCursor;
  EXEC tSQLt.Private_OutputTestResults @TestResultFormatter;
END;
GO

CREATE PROCEDURE tSQLt.RunSelected
  @Tag NVARCHAR(MAX) = NULL,
  @NamePattern NVARCHAR(MAX) = NULL,
  @TestResultFormatter NVARCHAR(MAX) = NULL
AS
BEGIN
  SET NOCOUNT ON;
  CREATE TABLE #SelectedTests(ObjectId INT,SchemaId INT,TestClassName SYSNAME COLLATE DATABASE_DEFAULT,TestCaseName SYSNAME COLLATE DATABASE_DEFAULT,FullName NVARCHAR(517) COLLATE DATABASE_DEFAULT);
  DECLARE @ReturnCode INT;
  EXEC @ReturnCode = tSQLt.Private_SelectTests @Tag,@NamePattern;
  IF @ReturnCode <> 0 RETURN -1;
  IF NOT EXISTS(SELECT 1 FROM #SelectedTests)
  BEGIN
    RAISERROR('No tests match the specified tag and name pattern.',16,10);
    RETURN -1;
  END;

  EXEC tSQLt.Private_RunMethodHandler @RunMethod = 'tSQLt.Private_RunSelected',
       @TestResultFormatter = @TestResultFormatter;
END;
GO
---Build-
