EXEC tSQLt.NewTestClass N'AssertTableCasesTests';
GO
CREATE PROCEDURE AssertTableCasesTests.[test equal rows and distinct UTF16 IDs preserve inputs]
AS
BEGIN
  CREATE TABLE #Cases(CaseId NVARCHAR(128),Expected DECIMAL(38,4),Actual DECIMAL(38,4),InputValue INT);
  INSERT #Cases VALUES(N'日本',9007199254740993,9007199254740993,1),
    (N'日本 ',NULL,NULL,2),(N' ',1.0001,1.0001,3);
  EXEC tSQLt.AssertTableCases N'#Cases',N'CaseId',N'Expected',N'Actual';
  DECLARE @Count INT=(SELECT COUNT(*) FROM #Cases);
  EXEC tSQLt.AssertEquals 3,@Count;
END;
GO
CREATE PROCEDURE AssertTableCasesTests.[test NULL empty and overlong case IDs are rejected]
AS
BEGIN
  CREATE TABLE #Cases(Id NVARCHAR(MAX),E INT,A INT);
  DECLARE @Ids TABLE(Id NVARCHAR(MAX));
  INSERT @Ids VALUES(NULL),(N''),(REPLICATE(N'x',129));
  DECLARE @Id NVARCHAR(MAX),@Caught BIT;
  DECLARE C CURSOR LOCAL FAST_FORWARD FOR SELECT Id FROM @Ids;
  OPEN C; FETCH NEXT FROM C INTO @Id;
  WHILE @@FETCH_STATUS=0
  BEGIN
    DELETE #Cases;
    INSERT #Cases VALUES(@Id,1,1);
    SET @Caught=0;
    BEGIN TRY
      EXEC tSQLt.AssertTableCases '#Cases','Id','E','A';
    END TRY
    BEGIN CATCH
      IF ERROR_MESSAGE() LIKE N'AssertTableCases: CaseId must%' SET @Caught=1;
      ELSE EXEC tSQLt.Fail N'Unexpected case ID validation error.';
    END CATCH;
    IF @Caught=0 EXEC tSQLt.Fail N'Invalid case ID was accepted.';
    FETCH NEXT FROM C INTO @Id;
  END;
  CLOSE C; DEALLOCATE C;
END;
GO
CREATE PROCEDURE AssertTableCasesTests.[test quoted regular table names work and produce no result rows]
AS
BEGIN
  CREATE TABLE AssertTableCasesTests.[日本'語]]表]([ID]]] NVARCHAR(10),E BIGINT,A BIGINT);
  INSERT AssertTableCasesTests.[日本'語]]表] VALUES(N'一',9007199254740993,9007199254740993);
  DECLARE @Before INT=(SELECT COUNT(*) FROM tSQLt.TestResult),@After INT;
  EXEC tSQLt.AssertTableCases N'AssertTableCasesTests.[日本''語]]表]',N'ID]',N'E',N'A';
  SELECT @After=COUNT(*) FROM tSQLt.TestResult;
  EXEC tSQLt.AssertEquals @Before,@After;
END;
GO
CREATE PROCEDURE AssertTableCasesTests.[test invalid table name cannot execute SQL]
AS
BEGIN
  CREATE TABLE #Cases(Id NVARCHAR(10),E INT,A INT);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern=N'AssertTableCases: specify an existing table%';
  EXEC tSQLt.AssertTableCases N'#Cases; DROP TABLE #Cases;',N'Id',N'E',N'A';
END;
GO
CREATE PROCEDURE AssertTableCasesTests.[test bulk calculation errors do not report successful cases]
AS
BEGIN
  EXEC tSQLt.NewTestClass N'TableCasesErrorFixture';
  EXEC(N'CREATE PROCEDURE TableCasesErrorFixture.[test calculation] AS
    CREATE TABLE #Cases(Id NVARCHAR(10),E INT,A INT);
    INSERT #Cases VALUES(N''one'',1,NULL);
    DECLARE @Zero INT=0;
    UPDATE #Cases SET A=E/@Zero;
    EXEC tSQLt.AssertTableCases ''#Cases'',''Id'',''E'',''A'';');
  EXEC tSQLt_testutil.AssertTestErrors N'TableCasesErrorFixture.test calculation',N'%Divide by zero%';
END;
GO
CREATE PROCEDURE AssertTableCasesTests.[test multiple mismatches include context and exact numeric differences]
AS
BEGIN
  CREATE TABLE #Cases(CaseId NVARCHAR(128),Expected DECIMAL(38,4),Actual DECIMAL(38,4),InputValue INT);
  INSERT #Cases VALUES(N'large',9007199254740993,9007199254740992,42),
    (N'money',1.0001,1.0002,43),(N'null',NULL,1,44);
  EXEC tSQLt_testutil.AssertFailMessageLike
    N'EXEC tSQLt.AssertTableCases N''#Cases'',N''CaseId'',N''Expected'',N''Actual'',N''context'';',
    N'context%Mismatches: 3; displayed: 3%9007199254740993.0000%9007199254740992.0000%InputValue=42%1.0001%1.0002%';
END;
GO
CREATE PROCEDURE AssertTableCasesTests.[test exact strings distinguish trailing spaces and zero characters]
AS
BEGIN
  CREATE TABLE #Cases(Id NVARCHAR(128),E NVARCHAR(MAX),A NVARCHAR(MAX));
  INSERT #Cases VALUES(N'1',N'abc',N'ABC ');
  EXEC tSQLt.AssertTableCases '#Cases','Id','E','A';
  EXEC tSQLt_testutil.AssertFailMessageLike
    N'EXEC tSQLt.AssertTableCases ''#Cases'',''Id'',''E'',''A'',@ExactStrings=1;',
    N'%Mismatches: 1; displayed: 1%';
  UPDATE #Cases SET E=REPLICATE(CONVERT(NVARCHAR(MAX),N'x'),5000)+NCHAR(0),A=REPLICATE(CONVERT(NVARCHAR(MAX),N'x'),5000);
  EXEC tSQLt_testutil.AssertFailMessageLike
    N'EXEC tSQLt.AssertTableCases ''#Cases'',''Id'',''E'',''A'',@ExactStrings=1;',
    N'%Mismatches: 1; displayed: 1%';
END;
GO
CREATE PROCEDURE AssertTableCasesTests.[test empty input is a usage error]
AS
BEGIN
  CREATE TABLE #Cases(Id NVARCHAR(10),E INT,A INT);
  EXEC tSQLt.ExpectException @ExpectedMessage=N'AssertTableCases: the input table is empty.';
  EXEC tSQLt.AssertTableCases '#Cases','Id','E','A';
END;
GO
CREATE PROCEDURE AssertTableCasesTests.[test invalid column is a usage error]
AS
BEGIN
  CREATE TABLE #Cases(Id NVARCHAR(10),E INT,A INT);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern=N'AssertTableCases: invalid columns%';
  EXEC tSQLt.AssertTableCases '#Cases','Id','missing','A';
END;
GO
CREATE PROCEDURE AssertTableCasesTests.[test mismatched types are a usage error]
AS
BEGIN
  CREATE TABLE #Cases(Id NVARCHAR(10),E BIGINT,A FLOAT);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern=N'AssertTableCases: Expected and Actual require%';
  EXEC tSQLt.AssertTableCases '#Cases','Id','E','A';
END;
GO
CREATE PROCEDURE AssertTableCasesTests.[test duplicate IDs are a usage error]
AS
BEGIN
  CREATE TABLE #Cases(Id NVARCHAR(10),E INT,A INT);
  INSERT #Cases VALUES(N'同',1,1),(N'同',1,1);
  EXEC tSQLt.ExpectException @ExpectedMessage=N'AssertTableCases: duplicate CaseId.';
  EXEC tSQLt.AssertTableCases '#Cases','Id','E','A';
END;
GO
CREATE PROCEDURE AssertTableCasesTests.[test diagnostics have a row and size limit]
AS
BEGIN
  CREATE TABLE #Cases(Id NVARCHAR(10),E INT,A INT);
  INSERT #Cases SELECT CONVERT(NVARCHAR(10),number),1,2 FROM
    (SELECT TOP(25) ROW_NUMBER() OVER(ORDER BY object_id) number FROM sys.objects) N;
  DECLARE @Message NVARCHAR(MAX);
  EXEC tSQLt_testutil.CaptureFailMessage
    N'EXEC tSQLt.AssertTableCases ''#Cases'',''Id'',''E'',''A'';',@Message OUTPUT;
  EXEC tSQLt.AssertLike N'%Mismatches: 25; displayed: 20 (truncated)%',@Message;
  IF DATALENGTH(@Message)>32000 EXEC tSQLt.Fail 'Diagnostic size exceeded.';
END;
GO
