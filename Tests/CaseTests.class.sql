EXEC tSQLt.NewTestClass 'CaseTests';
GO
CREATE PROCEDURE CaseTests.SetUp
AS
BEGIN
  EXEC tSQLt.FakeTable 'tSQLt.TestResult', @Identity = 1, @Defaults = 1, @ComputedColumns = 1;
  EXEC tSQLt.NewTestClass 'CaseFixture';
  EXEC('CREATE PROCEDURE CaseFixture.Cases AS
          INSERT #tSQLt_CaseList VALUES(N''A'',N''first''),(N''B'',N''second'');');
  EXEC('CREATE PROCEDURE CaseFixture.[test cases] @CaseId NVARCHAR(128) AS
        IF @CaseId = N''A'' EXEC tSQLt.Fail ''first failed'';');
  EXEC tSQLt.RegisterCaseTest 'CaseFixture.[test cases]', 'CaseFixture.Cases';
END;
GO
CREATE PROCEDURE CaseTests.[test selected tests expand registered cases]
AS
BEGIN
  EXEC(N'ALTER PROCEDURE CaseFixture.[test cases] @CaseId NVARCHAR(128) AS
    -'+N'-[@tSQLt:Tag](''case-selection'')
    IF @CaseId = N''A'' EXEC tSQLt.Fail ''first failed'';');
  EXEC tSQLt.RunSelected @Tag=N'case-selection', @NamePattern=N'CaseFixture.%',
    @TestResultFormatter=N'tSQLt.NullTestResultFormatter';
  DECLARE @Completed INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE CaseState='Completed');
  DECLARE @Failed INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result='Failure');
  EXEC tSQLt.AssertEquals 2, @Completed;
  EXEC tSQLt.AssertEquals 1, @Failed;
END;
GO
CREATE PROCEDURE CaseTests.[test seeded and replayed class runs expand registered cases]
AS
BEGIN
  DECLARE @Order XML, @Replayed XML;
  EXEC tSQLt.Run 'CaseFixture', 'tSQLt.NullTestResultFormatter', @Seed=123, @ExecutedOrder=@Order OUTPUT;
  DECLARE @Count INT = @Order.value('count(/TestOrder/Test)', 'INT');
  EXEC tSQLt.AssertEquals 1, @Count;
  SET @Count = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE CaseState='Completed');
  EXEC tSQLt.AssertEquals 2, @Count;
  EXEC tSQLt.Run 'CaseFixture', 'tSQLt.NullTestResultFormatter', @TestOrder=@Order, @ExecutedOrder=@Replayed OUTPUT;
  SET @Count = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE CaseState='Completed');
  EXEC tSQLt.AssertEquals 2, @Count;
  DECLARE @Expected NVARCHAR(MAX)=CONVERT(NVARCHAR(MAX),@Order), @Actual NVARCHAR(MAX)=CONVERT(NVARCHAR(MAX),@Replayed);
  EXEC tSQLt.AssertEqualsString @Expected, @Actual;
END;
GO
CREATE PROCEDURE CaseTests.[test positional seed argument remains compatible]
AS
BEGIN
  EXEC tSQLt.Run 'CaseFixture', 'tSQLt.NullTestResultFormatter', 123;
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE CaseState='Completed');
  EXEC tSQLt.AssertEquals 2, @Count;
END;
GO
CREATE PROCEDURE CaseTests.[test case selection cannot combine with execution order options]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessage='CaseId cannot be combined with execution order options.';
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter', @Seed=123, @CaseId='A';
END;
GO
CREATE PROCEDURE CaseTests.[test registration rejects procedures in other databases]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%procedures in the current database%';
  EXEC tSQLt.RegisterCaseTest 'master.dbo.test cases', 'CaseFixture.Cases';
END;
GO
CREATE PROCEDURE CaseTests.[test listing rejects procedures in other databases]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%procedures in the current database%';
  EXEC tSQLt.ListCases 'master.dbo.test cases';
END;
GO
CREATE PROCEDURE CaseTests.[test reporting rejects providers in other databases]
AS
BEGIN
  CREATE TABLE #tSQLt_CaseResults(CaseId NVARCHAR(MAX),Result NVARCHAR(MAX),Msg NVARCHAR(MAX));
  EXEC tSQLt.ReportCaseResults 'CaseFixture.[test cases]', 'master.dbo.Cases';
  DECLARE @Count INT=(SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result='Error' AND Msg LIKE '%procedures in the current database%');
  EXEC tSQLt.AssertEquals 1, @Count;
END;
GO
CREATE PROCEDURE CaseTests.[test list exposes stable identity and independent execution mode]
AS
BEGIN
  CREATE TABLE #Actual(TestName NVARCHAR(MAX) COLLATE DATABASE_DEFAULT,CaseId NVARCHAR(128) COLLATE DATABASE_DEFAULT,DisplayName NVARCHAR(512) COLLATE DATABASE_DEFAULT,ExecutionMode NVARCHAR(20) COLLATE DATABASE_DEFAULT);
  INSERT #Actual EXEC tSQLt.ListCases 'CaseFixture.[test cases]';
  SELECT N'[CaseFixture].[test cases]' TestName,N'A' CaseId,N'first' DisplayName,N'Independent' ExecutionMode INTO #Expected
  UNION ALL SELECT N'[CaseFixture].[test cases]',N'B',N'second',N'Independent';
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROCEDURE CaseTests.[test assertion failure does not prevent next case]
AS
BEGIN
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter';
  SELECT CaseId,CaseDisplayName,Result,CaseState INTO #Actual FROM tSQLt.TestResult;
  SELECT N'A' CaseId,N'first' CaseDisplayName,N'Failure' Result,N'Completed' CaseState INTO #Expected
  UNION ALL SELECT N'B',N'second',N'Success',N'Completed';
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROCEDURE CaseTests.[test SQL error does not prevent next case]
AS
BEGIN
  EXEC('ALTER PROCEDURE CaseFixture.[test cases] @CaseId NVARCHAR(128) AS
        IF @CaseId = N''A'' RAISERROR(''unexpected error'',16,1);');
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter';
  DECLARE @Errors INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE CaseId = 'A' AND Result = 'Error');
  DECLARE @Successes INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE CaseId = 'B' AND Result = 'Success');
  EXEC tSQLt.AssertEquals 1,@Errors;
  EXEC tSQLt.AssertEquals 1,@Successes;
END;
GO
CREATE PROCEDURE CaseTests.[test setup and rollback are repeated for each case]
AS
BEGIN
  CREATE TABLE CaseFixture.Work(Id INT);
  EXEC('CREATE PROCEDURE CaseFixture.SetUp AS INSERT CaseFixture.Work VALUES(1);');
  EXEC('ALTER PROCEDURE CaseFixture.[test cases] @CaseId NVARCHAR(128) AS
        DECLARE @Count INT = (SELECT COUNT(*) FROM CaseFixture.Work);
        EXEC tSQLt.AssertEquals 1,@Count;
        INSERT CaseFixture.Work VALUES(2);
        IF @CaseId = ''A'' RAISERROR(''first error'',16,1);');
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter';
  DECLARE @Result NVARCHAR(MAX) = (SELECT Result FROM tSQLt.TestResult WHERE CaseId = 'B');
  EXEC tSQLt.AssertEqualsString 'Success',@Result;
  EXEC tSQLt.AssertEmptyTable 'CaseFixture.Work';
END;
GO
CREATE PROCEDURE CaseTests.[test cleanup runs after body failure for every case]
AS
BEGIN
  EXEC('CREATE PROCEDURE CaseFixture.CleanUp AS RAISERROR(''cleanup ran'',16,1);');
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%cleanup ran%');
  EXEC tSQLt.AssertEquals 2,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test cleanup runs when setup fails]
AS
BEGIN
  EXEC('CREATE PROCEDURE CaseFixture.SetUp AS RAISERROR(''setup failed'',16,1);');
  EXEC('CREATE PROCEDURE CaseFixture.CleanUp AS RAISERROR(''cleanup ran'',16,1);');
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%setup failed%' AND Msg LIKE '%cleanup ran%');
  EXEC tSQLt.AssertEquals 2,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test TestName and CaseId select one case]
AS
BEGIN
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter', @CaseId = 'B';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult);
  DECLARE @Id NVARCHAR(128) = (SELECT CaseId FROM tSQLt.TestResult);
  EXEC tSQLt.AssertEquals 1,@Count;
  EXEC tSQLt.AssertEqualsString 'B',@Id;
END;
GO
CREATE PROCEDURE CaseTests.[test unknown CaseId is an error]
AS
BEGIN
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter', @CaseId = 'missing';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%does not exist%');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test duplicate identifiers are rejected before execution]
AS
BEGIN
  EXEC('ALTER PROCEDURE CaseFixture.Cases AS INSERT #tSQLt_CaseList VALUES(''A'',''one''),(''A'',''two'');');
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%duplicate%');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test empty enumeration is not success]
AS
BEGIN
  EXEC('ALTER PROCEDURE CaseFixture.Cases AS RETURN;');
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%no cases%');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test enumeration exceptions are reported]
AS
BEGIN
  EXEC('ALTER PROCEDURE CaseFixture.Cases AS RAISERROR(''discovery failed'',16,1);');
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%discovery failed%');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test identifiers are compared as exact UTF16 bytes]
AS
BEGIN
  EXEC('ALTER PROCEDURE CaseFixture.Cases AS INSERT #tSQLt_CaseList VALUES(N''a'',N''lower''),(N''A'',N''upper''),(N''A '',N''space'');');
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter', @CaseId = N'A ';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult);
  DECLARE @Name NVARCHAR(512) = (SELECT CaseDisplayName FROM tSQLt.TestResult);
  EXEC tSQLt.AssertEquals 1,@Count;
  EXEC tSQLt.AssertEqualsString 'space',@Name;
END;
GO
CREATE PROCEDURE CaseTests.[test invalid case metadata is rejected]
AS
BEGIN
  EXEC('ALTER PROCEDURE CaseFixture.Cases AS INSERT #tSQLt_CaseList VALUES(NULL,N''missing id'');');
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%nonempty%');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test case timing includes cleanup]
AS
BEGIN
  EXEC('CREATE PROCEDURE CaseFixture.CleanUp AS WAITFOR DELAY ''00:00:00.020'';');
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE TestEndTime >= DATEADD(MILLISECOND,20,TestStartTime));
  EXEC tSQLt.AssertEquals 2,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test planned cases remain errors when execution aborts]
AS
BEGIN
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest', @CommandToExecute = 'RAISERROR(''aborted'',16,1);';
  BEGIN TRY
    EXEC tSQLt.Private_RunCases 'CaseFixture.[test cases]';
  END TRY
  BEGIN CATCH
  END CATCH;
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE CaseState = 'NotRun' AND Result = 'Error' AND TestEndTime IS NULL);
  EXEC tSQLt.AssertEquals 2,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test missing results fail reconciliation]
AS
BEGIN
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest', @CommandToExecute = 'DELETE tSQLt.TestResult WHERE Id = @CaseResultId;';
  EXEC tSQLt.Private_RunCases 'CaseFixture.[test cases]';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%do not match%');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test XML contains case identity outcome and elapsed time]
AS
BEGIN
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_PrintXML';
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.XmlResultFormatter';
  DECLARE @Xml XML = (SELECT CONVERT(XML,Message) FROM tSQLt.Private_PrintXML_SpyProcedureLog);
  DECLARE @Count INT = @Xml.value('count(/testsuites/testsuite/testcase[@caseid])','int');
  DECLARE @Failures INT = @Xml.value('count(/testsuites/testsuite/testcase[@caseid="A"]/failure)','int');
  DECLARE @Timed INT = @Xml.value('count(/testsuites/testsuite/testcase[@executionmode="Independent"][@time])','int');
  EXEC tSQLt.AssertEquals 2,@Count;
  EXEC tSQLt.AssertEquals 1,@Failures;
  EXEC tSQLt.AssertEquals 2,@Timed;
END;
GO
CREATE PROCEDURE CaseTests.[test unregistered procedures retain procedure execution]
AS
BEGIN
  EXEC('CREATE PROCEDURE CaseFixture.[test legacy] AS RETURN;');
  EXEC tSQLt.Run 'CaseFixture.[test legacy]', 'tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Success' AND CaseId IS NULL AND CaseState IS NULL);
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test precomputed reports preserve missing cases as errors without timing]
AS
BEGIN
  EXEC('CREATE PROCEDURE CaseFixture.SetUp AS RAISERROR(''must not run setup'',16,1);');
  EXEC('CREATE PROCEDURE CaseFixture.CleanUp AS RAISERROR(''must not run cleanup'',16,1);');
  CREATE TABLE #tSQLt_CaseResults(CaseId NVARCHAR(MAX),Result NVARCHAR(MAX),Msg NVARCHAR(MAX));
  INSERT #tSQLt_CaseResults VALUES(N'A',N'Success',NULL);
  EXEC tSQLt.ReportCaseResults 'CaseFixture.[test cases]','CaseFixture.Cases';
  SELECT CaseId,Result,CaseState,CaseExecutionMode INTO #Actual FROM tSQLt.TestResult;
  SELECT N'A' CaseId,N'Success' Result,N'Reported' CaseState,N'Reported' CaseExecutionMode INTO #Expected
  UNION ALL SELECT N'B',N'Error',N'NotRun',N'Reported';
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
  DECLARE @Timed INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE TestEndTime IS NOT NULL);
  EXEC tSQLt.AssertEquals 0,@Timed;
END;
GO
CREATE PROCEDURE CaseTests.[test duplicate precomputed reports are errors]
AS
BEGIN
  CREATE TABLE #tSQLt_CaseResults(CaseId NVARCHAR(MAX),Result NVARCHAR(MAX),Msg NVARCHAR(MAX));
  INSERT #tSQLt_CaseResults VALUES(N'A',N'Success',NULL),(N'A',N'Success',NULL);
  EXEC tSQLt.ReportCaseResults 'CaseFixture.[test cases]','CaseFixture.Cases';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%duplicate%');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test unexpected precomputed reports are errors]
AS
BEGIN
  CREATE TABLE #tSQLt_CaseResults(CaseId NVARCHAR(MAX),Result NVARCHAR(MAX),Msg NVARCHAR(MAX));
  INSERT #tSQLt_CaseResults VALUES(N'unknown',N'Success',NULL);
  EXEC tSQLt.ReportCaseResults 'CaseFixture.[test cases]','CaseFixture.Cases';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%unplanned%');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test reported XML never claims independent execution or measured time]
AS
BEGIN
  CREATE TABLE #tSQLt_CaseResults(CaseId NVARCHAR(MAX),Result NVARCHAR(MAX),Msg NVARCHAR(MAX));
  INSERT #tSQLt_CaseResults VALUES(N'A',N'Failure',N'<mismatch & details>');
  EXEC tSQLt.ReportCaseResults 'CaseFixture.[test cases]','CaseFixture.Cases';
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_PrintXML';
  EXEC tSQLt.XmlResultFormatter;
  DECLARE @Xml XML = (SELECT CONVERT(XML,Message) FROM tSQLt.Private_PrintXML_SpyProcedureLog);
  DECLARE @Reported INT = @Xml.value('count(/testsuites/testsuite/testcase[@executionmode="Reported"])','int');
  DECLARE @Timed INT = @Xml.value('count(/testsuites/testsuite/testcase[@time])','int');
  DECLARE @Errors INT = @Xml.value('count(/testsuites/testsuite/testcase[@state="NotRun"]/error)','int');
  DECLARE @Message NVARCHAR(MAX) = @Xml.value('(/testsuites/testsuite/testcase[@caseid="A"]/failure/@message)[1]','nvarchar(max)');
  EXEC tSQLt.AssertEquals 2,@Reported;
  EXEC tSQLt.AssertEquals 0,@Timed;
  EXEC tSQLt.AssertEquals 1,@Errors;
  EXEC tSQLt.AssertEqualsString '<mismatch & details>',@Message;
END;
GO
CREATE PROCEDURE CaseTests.[test NoTransaction cannot bypass case isolation]
AS
BEGIN
  EXEC('--[@'+'tSQLt:NoTransaction](DEFAULT)
        ALTER PROCEDURE CaseFixture.[test cases] @CaseId NVARCHAR(128) AS RETURN;');
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%require transaction isolation%');
  EXEC tSQLt.AssertEquals 2,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test class execution expands registered tests into cases]
AS
BEGIN
  EXEC tSQLt.Run 'CaseFixture','tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE CaseState = 'Completed');
  EXEC tSQLt.AssertEquals 2,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test overly long selectors are not silently truncated]
AS
BEGIN
  EXEC('ALTER PROCEDURE CaseFixture.Cases AS INSERT #tSQLt_CaseList VALUES(REPLICATE(N''A'',128),N''long id'');');
  DECLARE @Id NVARCHAR(MAX) = REPLICATE(N'A',129);
  EXEC tSQLt.Run 'CaseFixture.[test cases]', 'tSQLt.NullTestResultFormatter', @CaseId = @Id;
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%does not exist%');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test unexpected execution results fail reconciliation]
AS
BEGIN
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest', @CommandToExecute = '
    UPDATE tSQLt.TestResult SET CaseState = ''Completed'', Result = ''Success'' WHERE Id = @CaseResultId;
    INSERT tSQLt.TestResult(Class,TestCase,CaseId,Result) VALUES(''CaseFixture'',''test cases'',''extra'',''Success'');';
  EXEC tSQLt.Private_RunCases 'CaseFixture.[test cases]';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error' AND Msg LIKE '%do not match%');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test listing invalid cases raises an error]
AS
BEGIN
  EXEC('ALTER PROCEDURE CaseFixture.Cases AS INSERT #tSQLt_CaseList VALUES('''',''empty id'');');
  EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%nonempty%';
  EXEC tSQLt.ListCases 'CaseFixture.[test cases]';
END;
GO
CREATE PROCEDURE CaseTests.[test registration requires an explicit CaseId parameter]
AS
BEGIN
  EXEC('CREATE PROCEDURE CaseFixture.[test legacy] AS RETURN;');
  EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%must accept @CaseId%';
  EXEC tSQLt.RegisterCaseTest 'CaseFixture.[test legacy]','CaseFixture.Cases';
END;
GO
CREATE PROCEDURE CaseTests.[test case selection cannot target an entire class]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%requires a registered case test%';
  EXEC tSQLt.Run 'CaseFixture','tSQLt.NullTestResultFormatter',@CaseId = 'A';
END;
GO
CREATE PROCEDURE CaseTests.[test case execution uses a parameter for quoted identifiers]
AS
BEGIN
  EXEC('ALTER PROCEDURE CaseFixture.Cases AS INSERT #tSQLt_CaseList VALUES(N''x''''; special & <id>'',N''special display'');');
  EXEC('ALTER PROCEDURE CaseFixture.[test cases] @CaseId NVARCHAR(128) AS
          EXEC tSQLt.AssertEqualsString N''x''''; special & <id>'', @CaseId;');
  EXEC tSQLt.Run 'CaseFixture.[test cases]','tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Success');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE CaseTests.[test assertion expectations do not leak between cases]
AS
BEGIN
  EXEC('ALTER PROCEDURE CaseFixture.[test cases] @CaseId NVARCHAR(128) AS
          IF @CaseId = ''A'' BEGIN
            EXEC tSQLt.ExpectException;
            RAISERROR(''expected only for A'',16,1);
          END;');
  EXEC tSQLt.Run 'CaseFixture.[test cases]','tSQLt.NullTestResultFormatter';
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Success');
  EXEC tSQLt.AssertEquals 2,@Count;
END;
GO
