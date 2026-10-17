EXEC tSQLt.NewTestClass 'SelectedTestsTests';
GO
CREATE PROCEDURE SelectedTestsTests.SetUp
AS
BEGIN
  EXEC tSQLt.NewTestClass 'SelectedFixture';
  EXEC(N'CREATE PROCEDURE SelectedFixture.[test smoke] AS
    -'+N'-[@tSQLt:Tag](''smoke'')
    -'+N'-[@tSQLt:Tag](''smoke'')
    -'+N'-[@tSQLt:Tag](N''integration'')
    RETURN;');
  EXEC(N'CREATE PROCEDURE SelectedFixture.[test slow] AS
    -'+N'-[@tSQLt:Tag](''slow'')
    RETURN;');
  EXEC(N'CREATE PROCEDURE SelectedFixture.[test untagged] AS RETURN;');
  EXEC(N'CREATE PROCEDURE SelectedFixture.Helper AS RETURN;');
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test tag selection deduplicates and matches any tag]
AS
BEGIN
  CREATE TABLE #Actual(TestClassName SYSNAME,TestCaseName SYSNAME,FullName NVARCHAR(517));
  INSERT INTO #Actual EXEC tSQLt.ListTests @Tag=N'integration',@NamePattern=N'SelectedFixture.%';
  SELECT TOP(0) * INTO #Expected FROM #Actual;
  INSERT INTO #Expected VALUES(N'SelectedFixture',N'test smoke',N'[SelectedFixture].[test smoke]');
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
  TRUNCATE TABLE #Actual;
  INSERT INTO #Actual EXEC tSQLt.ListTests @Tag=N'smoke',@NamePattern=N'SelectedFixture.%';
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test name selection uses full unquoted name and SQL LIKE]
AS
BEGIN
  CREATE TABLE #Actual(TestClassName SYSNAME,TestCaseName SYSNAME,FullName NVARCHAR(517));
  INSERT INTO #Actual EXEC tSQLt.ListTests @NamePattern=N'SelectedFixture.test s[ml]o_e';
  SELECT TOP(0) * INTO #Expected FROM #Actual;
  INSERT INTO #Expected VALUES(N'SelectedFixture',N'test smoke',N'[SelectedFixture].[test smoke]');
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test tag and name filters intersect]
AS
BEGIN
  CREATE TABLE #Actual(TestClassName SYSNAME,TestCaseName SYSNAME,FullName NVARCHAR(517));
  INSERT INTO #Actual EXEC tSQLt.ListTests @Tag=N'smoke',@NamePattern=N'SelectedFixture.test slow';
  EXEC tSQLt.AssertEmptyTable '#Actual';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test omitted filters list exactly registered tests]
AS
BEGIN
  CREATE TABLE #Actual(TestClassName SYSNAME,TestCaseName SYSNAME,FullName NVARCHAR(517));
  INSERT INTO #Actual EXEC tSQLt.ListTests;
  SELECT TestClassName,Name AS TestCaseName,QUOTENAME(TestClassName)+N'.'+QUOTENAME(Name) AS FullName
    INTO #Expected FROM tSQLt.Tests;
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test name-only selection includes untagged tests and excludes helpers]
AS
BEGIN
  CREATE TABLE #Actual(TestClassName SYSNAME,TestCaseName SYSNAME,FullName NVARCHAR(517));
  INSERT INTO #Actual EXEC tSQLt.ListTests @NamePattern=N'SelectedFixture.%';
  DECLARE @Count INT=(SELECT COUNT(*) FROM #Actual);
  EXEC tSQLt.AssertEquals 3,@Count;
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test Unicode quotes whitespace and special identifiers are supported]
AS
BEGIN
  DECLARE @Cmd NVARCHAR(MAX)=N'CREATE PROCEDURE SelectedFixture.[test 日本語 ]]] AS
    -'+N'-[@tSQLt:Tag] '+NCHAR(9)+N'( N''日本語''''tag'' ) '+NCHAR(9)+N'
    RETURN;';
  EXEC(@Cmd);
  CREATE TABLE #Actual(TestClassName SYSNAME,TestCaseName SYSNAME,FullName NVARCHAR(517));
  INSERT INTO #Actual EXEC tSQLt.ListTests @Tag=N'日本語''tag',@NamePattern=N'SelectedFixture.%';
  SELECT TOP(0) * INTO #Expected FROM #Actual;
  INSERT INTO #Expected VALUES(N'SelectedFixture',N'test 日本語 ]',N'[SelectedFixture].[test 日本語 ]]]');
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test trailing spaces in tag values are significant]
AS
BEGIN
  CREATE TABLE #Actual(TestClassName SYSNAME,TestCaseName SYSNAME,FullName NVARCHAR(517));
  INSERT INTO #Actual EXEC tSQLt.ListTests @Tag=N'smoke ',@NamePattern=N'SelectedFixture.%';
  EXEC tSQLt.AssertEmptyTable '#Actual';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test listing does not run tests helpers or other annotations and preserves results]
AS
BEGIN
  EXEC(N'CREATE PROCEDURE SelectedFixture.SetUp AS EXEC tSQLt.Fail ''SetUp executed'';');
  EXEC(N'CREATE PROCEDURE SelectedFixture.CleanUp AS EXEC tSQLt.Fail ''CleanUp executed'';');
  EXEC(N'ALTER PROCEDURE SelectedFixture.[test smoke] AS
    -'+N'-[@tSQLt:Tag](''smoke'')
    -'+N'-[@tSQLt:DoesNotExist]()
    EXEC tSQLt.Fail ''body executed'';');
  SELECT * INTO #Before FROM tSQLt.TestResult;
  CREATE TABLE #Actual(TestClassName SYSNAME,TestCaseName SYSNAME,FullName NVARCHAR(517));
  INSERT INTO #Actual EXEC tSQLt.ListTests @Tag=N'smoke',@NamePattern=N'SelectedFixture.%';
  EXEC tSQLt.AssertEqualsTable '#Before','tSQLt.TestResult';
  DECLARE @ActualCount INT=(SELECT COUNT(*) FROM #Actual); EXEC tSQLt.AssertEquals 1,@ActualCount;
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test invalid tag syntax identifies test before running appended SQL]
AS
BEGIN
  EXEC(N'ALTER PROCEDURE SelectedFixture.[test smoke] AS
    -'+N'-[@tSQLt:Tag](''smoke''); RAISERROR(''injected'',16,1);
    RETURN;');
  EXEC tSQLt.ExpectException @ExpectedMessage=N'Invalid Tag annotation on test [SelectedFixture].[test smoke]. Expected a single nonempty string literal.';
  EXEC tSQLt.ListTests @Tag=N'smoke',@NamePattern=N'SelectedFixture.%';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test invalid annotations outside name filter do not prevent selection]
AS
BEGIN
  EXEC(N'ALTER PROCEDURE SelectedFixture.[test slow] AS
    -'+N'-[@tSQLt:Tag](1+2)
    RETURN;');
  EXEC tSQLt.RunSelected @Tag=N'smoke',@NamePattern=N'SelectedFixture.test smoke',@TestResultFormatter=N'tSQLt.NullTestResultFormatter';
  DECLARE @Count1 INT=(SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result='Success'); EXEC tSQLt.AssertEquals 1,@Count1;
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test empty tag filter is rejected]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessage=N'Tag must not be empty or whitespace.';
  EXEC tSQLt.ListTests @Tag=N'';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test whitespace tag filter is rejected]
AS
BEGIN
  DECLARE @Tag NVARCHAR(MAX)=N' '+NCHAR(9)+NCHAR(10)+NCHAR(13);
  EXEC tSQLt.ExpectException @ExpectedMessage=N'Tag must not be empty or whitespace.';
  EXEC tSQLt.RunSelected @Tag=@Tag;
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test empty run errors before initialization and preserves results]
AS
BEGIN
  SELECT * INTO #Before FROM tSQLt.TestResult;
  DECLARE @Message NVARCHAR(MAX);
  BEGIN TRY
    EXEC tSQLt.RunSelected @NamePattern=N'SelectedFixture.no such test';
  END TRY
  BEGIN CATCH
    SET @Message=ERROR_MESSAGE();
  END CATCH;
  EXEC tSQLt.AssertEqualsString N'No tests match the specified tag and name pattern.',@Message;
  EXEC tSQLt.AssertEqualsTable '#Before','tSQLt.TestResult';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test listing and execution select the same tests]
AS
BEGIN
  CREATE TABLE #Listed(TestClassName SYSNAME,TestCaseName SYSNAME,FullName NVARCHAR(517));
  INSERT INTO #Listed EXEC tSQLt.ListTests @Tag=N'smoke',@NamePattern=N'SelectedFixture.%';
  EXEC tSQLt.RunSelected @Tag=N'smoke',@NamePattern=N'SelectedFixture.%',@TestResultFormatter=N'tSQLt.NullTestResultFormatter';
  SELECT Class AS TestClassName,TestCase AS TestCaseName,Name AS FullName INTO #Actual FROM tSQLt.TestResult;
  EXEC tSQLt.AssertEqualsTable '#Listed','#Actual';
  DECLARE @Count1 INT=(SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result='Success'); EXEC tSQLt.AssertEquals 1,@Count1;
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test selected tests use SetUp and rollback]
AS
BEGIN
  EXEC(N'CREATE PROCEDURE SelectedFixture.SetUp AS CREATE TABLE SelectedFixture.Marker(I INT);');
  EXEC(N'ALTER PROCEDURE SelectedFixture.[test smoke] AS
    -'+N'-[@tSQLt:Tag](''smoke'')
    EXEC tSQLt.AssertObjectExists ''SelectedFixture.Marker'';');
  EXEC tSQLt.RunSelected @Tag=N'smoke',@NamePattern=N'SelectedFixture.%',@TestResultFormatter=N'tSQLt.NullTestResultFormatter';
  DECLARE @Count1 INT=(SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result='Success'); EXEC tSQLt.AssertEquals 1,@Count1;
  EXEC tSQLt.AssertObjectDoesNotExist 'SelectedFixture.Marker';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test selected skipped tests remain in listing and skip at execution]
AS
BEGIN
  EXEC(N'ALTER PROCEDURE SelectedFixture.[test smoke] AS
    -'+N'-[@tSQLt:Tag](''smoke'')
    -'+N'-[@tSQLt:SkipTest](''skip selected test'')
    EXEC tSQLt.Fail ''body executed'';');
  EXEC tSQLt.RunSelected @Tag=N'smoke',@NamePattern=N'SelectedFixture.%',@TestResultFormatter=N'tSQLt.NullTestResultFormatter';
  DECLARE @Count1 INT=(SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result='Skipped'); EXEC tSQLt.AssertEquals 1,@Count1;
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test explicit and configured result formatters are used]
AS
BEGIN
  EXEC(N'CREATE PROCEDURE SelectedFixture.Formatter AS INSERT INTO #FormatterCalls DEFAULT VALUES;');
  CREATE TABLE #FormatterCalls(I INT IDENTITY);
  EXEC tSQLt.RunSelected @NamePattern=N'SelectedFixture.test slow',@TestResultFormatter=N'SelectedFixture.Formatter';
  DECLARE @Count1 INT=(SELECT COUNT(*) FROM #FormatterCalls); EXEC tSQLt.AssertEquals 1,@Count1;
  EXEC tSQLt.SetTestResultFormatter 'SelectedFixture.Formatter';
  EXEC tSQLt.RunSelected @NamePattern=N'SelectedFixture.test slow';
  DECLARE @Count2 INT=(SELECT COUNT(*) FROM #FormatterCalls); EXEC tSQLt.AssertEquals 2,@Count2;
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test ordinary Run accepts tag metadata]
AS
BEGIN
  EXEC tSQLt.Run 'SelectedFixture.test smoke','tSQLt.NullTestResultFormatter';
  DECLARE @Count1 INT=(SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result='Success'); EXEC tSQLt.AssertEquals 1,@Count1;
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test invalid tag forms are rejected without evaluating expressions]
AS
BEGIN
  DECLARE @Forms TABLE(Id INT IDENTITY,Arguments NVARCHAR(MAX));
  INSERT INTO @Forms VALUES(N'()'),(N'(NULL)'),(N'(42)'),(N'(''smoke''+''slow'')'),
    (N'(''smoke'',''slow'')'),(N'('''')'),(N'(''   '')'),(N'(''unclosed)'),(N'(''smoke'') extra');
  DECLARE @Id INT=1,@Arguments NVARCHAR(MAX),@Cmd NVARCHAR(MAX),@Message NVARCHAR(MAX);
  WHILE EXISTS(SELECT 1 FROM @Forms WHERE Id=@Id)
  BEGIN
    SELECT @Arguments=Arguments FROM @Forms WHERE Id=@Id;
    SET @Cmd=N'ALTER PROCEDURE SelectedFixture.[test smoke] AS
      -'+N'-[@tSQLt:Tag]'+@Arguments+N'
      RETURN;';
    EXEC(@Cmd);
    SET @Message=NULL;
    BEGIN TRY
      EXEC tSQLt.ListTests @Tag=N'smoke',@NamePattern=N'SelectedFixture.test smoke';
    END TRY
    BEGIN CATCH
      SET @Message=ERROR_MESSAGE();
    END CATCH;
    EXEC tSQLt.AssertEqualsString
      N'Invalid Tag annotation on test [SelectedFixture].[test smoke]. Expected a single nonempty string literal.',@Message;
    SET @Id=@Id+1;
  END;
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test NoTransaction tests use class SetUp and CleanUp]
AS
BEGIN
  EXEC(N'CREATE PROCEDURE SelectedFixture.SetUp AS CREATE TABLE SelectedFixture.Marker(I INT);');
  EXEC(N'CREATE PROCEDURE SelectedFixture.CleanUp AS DROP TABLE SelectedFixture.Marker;');
  EXEC(N'ALTER PROCEDURE SelectedFixture.[test smoke] AS
    -'+N'-[@tSQLt:Tag](''smoke'')
    -'+N'-[@tSQLt:NoTransaction](DEFAULT)
    EXEC tSQLt.AssertObjectExists ''SelectedFixture.Marker'';');
  EXEC tSQLt.RunSelected @Tag=N'smoke',@NamePattern=N'SelectedFixture.%',@TestResultFormatter=N'tSQLt.NullTestResultFormatter';
  DECLARE @Count INT=(SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result='Success');
  EXEC tSQLt.AssertEquals 1,@Count;
  EXEC tSQLt.AssertObjectDoesNotExist 'SelectedFixture.Marker';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test no filters execute all discovered tests]
AS
BEGIN
  -- Restrict discovery to the fixture so this test does not recursively run itself.
  SELECT * INTO #Tests FROM tSQLt.Tests WHERE TestClassName=N'SelectedFixture';
  EXEC tSQLt.FakeTable 'tSQLt.Tests';
  INSERT INTO tSQLt.Tests SELECT * FROM #Tests;
  EXEC tSQLt.RunSelected @TestResultFormatter=N'tSQLt.NullTestResultFormatter';
  DECLARE @Count INT=(SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result='Success');
  EXEC tSQLt.AssertEquals 3,@Count;
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test name-only selection does not parse tag annotations]
AS
BEGIN
  EXEC(N'ALTER PROCEDURE SelectedFixture.[test smoke] AS
    -'+N'-[@tSQLt:Tag](NULL)
    RETURN;');
  CREATE TABLE #Actual(TestClassName SYSNAME,TestCaseName SYSNAME,FullName NVARCHAR(517));
  INSERT INTO #Actual EXEC tSQLt.ListTests @NamePattern=N'SelectedFixture.test smoke';
  DECLARE @Count INT=(SELECT COUNT(*) FROM #Actual);
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test tag with missing closing bracket is rejected]
AS
BEGIN
  EXEC(N'ALTER PROCEDURE SelectedFixture.[test smoke] AS
    -'+N'-[@tSQLt:Tag(''smoke'')
    RETURN;');
  EXEC tSQLt.ExpectException
    @ExpectedMessage=N'Invalid Tag annotation on test [SelectedFixture].[test smoke]. Expected a single nonempty string literal.';
  EXEC tSQLt.ListTests @Tag=N'smoke',@NamePattern=N'SelectedFixture.%';
END;
GO

CREATE PROCEDURE SelectedTestsTests.[test other annotations starting with Tag are ignored when listing]
AS
BEGIN
  EXEC(N'ALTER PROCEDURE SelectedFixture.[test smoke] AS
    -'+N'-[@tSQLt:Tag](''smoke'')
    -'+N'-[@tSQLt:TagSomethingElse](arbitrary SQL)
    RETURN;');
  CREATE TABLE #Actual(TestClassName SYSNAME,TestCaseName SYSNAME,FullName NVARCHAR(517));
  INSERT INTO #Actual EXEC tSQLt.ListTests @Tag=N'smoke',@NamePattern=N'SelectedFixture.%';
  DECLARE @Count INT=(SELECT COUNT(*) FROM #Actual);
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
