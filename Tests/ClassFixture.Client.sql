-- Run on a dedicated validation database, outside a tSQLt test transaction.
SET NOCOUNT ON;
EXEC tSQLt.SetSummaryError 0;
EXEC tSQLt.NewTestClass N'FixtureClient';
CREATE TABLE FixtureClient.Data(Id INT);
INSERT FixtureClient.Data VALUES(99);
CREATE SEQUENCE FixtureClient.SetupCount START WITH 1;
EXEC(N'CREATE PROCEDURE FixtureClient.Target AS RETURN;');
EXEC(N'CREATE PROCEDURE FixtureClient.ClassSetUp AS
  DECLARE @Invocation BIGINT=NEXT VALUE FOR FixtureClient.SetupCount;
  EXEC tSQLt.FakeTable N''FixtureClient.Data'';
  INSERT FixtureClient.Data VALUES(1);
  EXEC tSQLt.SpyProcedure N''FixtureClient.Target'';');
EXEC(N'CREATE PROCEDURE FixtureClient.[test A] AS
  EXEC tSQLt.AssertEqualsTable ''FixtureClient.Data'',''FixtureClient.Data'';
  IF (SELECT COUNT(*) FROM FixtureClient.Data)<>1 OR NOT EXISTS(SELECT 1 FROM FixtureClient.Data WHERE Id=1)
    EXEC tSQLt.Fail ''Fixture data leaked.'';
  EXEC tSQLt.AssertProcedureNotCalled N''FixtureClient.Target'';
  UPDATE FixtureClient.Data SET Id=2;
  EXEC FixtureClient.Target;');
EXEC(N'CREATE PROCEDURE FixtureClient.[test B] AS
  IF (SELECT COUNT(*) FROM FixtureClient.Data)<>1 OR NOT EXISTS(SELECT 1 FROM FixtureClient.Data WHERE Id=1)
    EXEC tSQLt.Fail ''Fixture data leaked.'';
  EXEC tSQLt.AssertProcedureNotCalled N''FixtureClient.Target'';');
EXEC tSQLt.RegisterClassFixture N'FixtureClient',N'FixtureClient.ClassSetUp';
DECLARE @Order XML;
EXEC tSQLt.Run N'FixtureClient',@Seed=42,@ExecutedOrder=@Order OUTPUT;
IF (SELECT COUNT(*) FROM tSQLt.TestResult)<>2 OR EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Result<>N'Success')
  RAISERROR('Fixture isolation failed.',16,10);
IF (SELECT CONVERT(BIGINT,current_value) FROM sys.sequences WHERE object_id=OBJECT_ID(N'FixtureClient.SetupCount'))<>1
  RAISERROR('ClassSetUp executed more than once.',16,10);
IF NOT EXISTS(SELECT 1 FROM FixtureClient.Data WHERE Id=99) OR OBJECT_ID('FixtureClient.Target_SpyProcedureLog') IS NOT NULL
  RAISERROR('Fixture rollback did not restore objects.',16,10);
EXEC tSQLt.Run N'FixtureClient',@TestOrder=@Order;
IF EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Result<>N'Success') RAISERROR('Fixture replay failed.',16,10);
EXEC tSQLt.Run N'FixtureClient.test A';
IF (SELECT COUNT(*) FROM tSQLt.TestResult)<>1 OR EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Result<>N'Success')
  RAISERROR('Single fixture test failed.',16,10);
EXEC tSQLt.RunSelected @NamePattern=N'FixtureClient.test %';
IF (SELECT COUNT(*) FROM tSQLt.TestResult)<>2 OR EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Result<>N'Success')
  RAISERROR('Selected fixture tests failed.',16,10);

-- Case providers run before ClassSetUp and are evaluated only once.
EXEC(N'CREATE PROCEDURE FixtureClient.Provider AS
  IF NOT EXISTS(SELECT 1 FROM FixtureClient.Data WHERE Id=99) RAISERROR(''Provider ran after setup.'',16,10);
  INSERT #tSQLt_CaseList VALUES(N''一'',N''one''),(N''二'',N''two'');');
EXEC(N'CREATE PROCEDURE FixtureClient.[test Cases] @CaseId NVARCHAR(128) AS
  IF NOT EXISTS(SELECT 1 FROM FixtureClient.Data WHERE Id=1) EXEC tSQLt.Fail ''Case fixture missing.'';
  UPDATE FixtureClient.Data SET Id=2;');
EXEC tSQLt.RegisterCaseTest N'FixtureClient.test Cases',N'FixtureClient.Provider';
EXEC tSQLt.Run N'FixtureClient.test Cases',@CaseId=N'二';
IF (SELECT COUNT(*) FROM tSQLt.TestResult)<>1 OR EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Result<>N'Success' OR CaseId<>N'二')
  RAISERROR('Single fixture case failed.',16,10);
EXEC tSQLt.RunAll;
IF (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Class=N'FixtureClient')<>4 OR EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Result<>N'Success')
  RAISERROR('RunAll fixture scope failed.',16,10);
EXEC tSQLt.Reset;
EXEC tSQLt.NewTestClass N'FixtureSecond';
EXEC(N'CREATE PROCEDURE FixtureSecond.Prepare AS RETURN;');
EXEC(N'CREATE PROCEDURE FixtureSecond.[test success] AS RETURN;');
EXEC tSQLt.RegisterClassFixture N'FixtureSecond',N'FixtureSecond.Prepare';
EXEC tSQLt.RunNew;
IF (SELECT COUNT(*) FROM tSQLt.TestResult)<>1 OR EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Class<>N'FixtureSecond' OR Result<>N'Success')
  RAISERROR('RunNew fixture scope failed.',16,10);
EXEC tSQLt.DropClass N'FixtureSecond';

-- Ordinary failure keeps the fixture alive; a full rollback stops the remainder.
EXEC(N'CREATE PROCEDURE FixtureClient.[test Fail] AS EXEC tSQLt.Fail N''expected failure'';');
EXEC tSQLt.Run N'FixtureClient',@TestOrder=N'<TestOrder version="1" class="FixtureClient"><Test ordinal="1" name="test Fail"/><Test ordinal="2" name="test B"/></TestOrder>';
IF (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result=N'Failure')<>1
   OR (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result=N'Success')<>1
  RAISERROR('Normal failure lost results or fixture.',16,10);
EXEC(N'CREATE PROCEDURE FixtureClient.[test Rollback] AS ROLLBACK;');
EXEC tSQLt.Run N'FixtureClient',@TestOrder=N'<TestOrder version="1" class="FixtureClient"><Test ordinal="1" name="test B"/><Test ordinal="2" name="test Rollback"/><Test ordinal="3" name="test A"/></TestOrder>';
IF (SELECT COUNT(*) FROM tSQLt.TestResult)<>3
   OR (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result=N'Success')<>1
   OR (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result=N'Error')<>2 OR @@TRANCOUNT<>0
  RAISERROR('Rollback lost result buffer or leaked transaction.',16,10);

EXEC(N'ALTER PROCEDURE FixtureClient.ClassSetUp AS RAISERROR(''Setup failed deliberately.'',16,10);');
EXEC tSQLt.Run N'FixtureClient',@TestOrder=N'<TestOrder version="1" class="FixtureClient"><Test ordinal="1" name="test A"/><Test ordinal="2" name="test B"/></TestOrder>';
IF (SELECT COUNT(*) FROM tSQLt.TestResult)<>2 OR EXISTS(SELECT 1 FROM tSQLt.TestResult WHERE Result<>N'Error')
  RAISERROR('Setup failure did not account for planned tests.',16,10);
EXEC(N'ALTER PROCEDURE FixtureClient.ClassSetUp AS RETURN;');
EXEC(N'CREATE PROCEDURE FixtureClient.[test Nested] AS EXEC tSQLt.Run N''FixtureClient.test B'';');
EXEC tSQLt.Run N'FixtureClient.test Nested';
IF (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result=N'Error' AND Msg LIKE N'%Nested test execution%')<>1
  RAISERROR('Nested fixture execution was not rejected.',16,10);
EXEC(N'CREATE PROCEDURE FixtureClient.[test Ok] AS RETURN;');
EXEC(N'CREATE PROCEDURE FixtureClient.[test CommitBegin] AS
  WHILE @@TRANCOUNT>0 COMMIT;
  BEGIN TRAN;
  BEGIN TRAN;');
EXEC tSQLt.Run N'FixtureClient',@TestOrder=N'<TestOrder version="1" class="FixtureClient"><Test ordinal="1" name="test Ok"/><Test ordinal="2" name="test CommitBegin"/><Test ordinal="3" name="test B"/></TestOrder>';
IF (SELECT COUNT(*) FROM tSQLt.TestResult)<>3
   OR (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result=N'Success')<>1
   OR (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result=N'Error')<>2 OR @@TRANCOUNT<>0
  RAISERROR('Replacement transaction was not detected.',16,10);
EXEC(N'CREATE PROCEDURE FixtureClient.[test Doomed] AS
  SET XACT_ABORT ON;
  CREATE TABLE #Doomed(Id INT PRIMARY KEY);
  INSERT #Doomed VALUES(1);
  BEGIN TRY
    INSERT #Doomed VALUES(1);
  END TRY
  BEGIN CATCH
    EXEC tSQLt.Fail N''Doomed assertion'';
  END CATCH;');
EXEC tSQLt.Run N'FixtureClient',@TestOrder=N'<TestOrder version="1" class="FixtureClient"><Test ordinal="1" name="test Ok"/><Test ordinal="2" name="test Doomed"/><Test ordinal="3" name="test B"/></TestOrder>';
IF (SELECT COUNT(*) FROM tSQLt.TestResult)<>3
   OR (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result=N'Success')<>1
   OR (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result=N'Error')<>2 OR @@TRANCOUNT<>0
  RAISERROR('Doomed transaction lost buffered results.',16,10);

DECLARE @Rejected BIT=0;
BEGIN TRAN;
BEGIN TRY
  EXEC tSQLt.Run N'FixtureClient.test B';
END TRY
BEGIN CATCH
  IF ERROR_MESSAGE() LIKE N'%no caller transaction%' SET @Rejected=1;
END CATCH;
ROLLBACK;
IF @Rejected=0 RAISERROR('Caller transaction was accepted.',16,10);
EXEC(N'CREATE PROCEDURE FixtureClient.[test NoTran]
--[@tSQLt:NoTransaction]
AS RETURN;');
SET @Rejected=0;
BEGIN TRY
  EXEC tSQLt.Run N'FixtureClient.test NoTran';
END TRY
BEGIN CATCH
  IF ERROR_MESSAGE() LIKE N'%NoTransaction%' SET @Rejected=1;
END CATCH;
IF @Rejected=0 RAISERROR('NoTransaction was accepted.',16,10);
EXEC tSQLt.RegisterClassFixture N'FixtureClient',NULL;
IF EXISTS(SELECT 1 FROM tSQLt.Private_ClassFixture WHERE ClassId=SCHEMA_ID(N'FixtureClient'))
  RAISERROR('Fixture unregister failed.',16,10);
EXEC tSQLt.RegisterClassFixture N'FixtureClient',N'FixtureClient.ClassSetUp';
DECLARE @OldClassId INT=SCHEMA_ID(N'FixtureClient');
EXEC tSQLt.DropClass N'FixtureClient';
IF EXISTS(SELECT 1 FROM tSQLt.Private_ClassFixture WHERE ClassId=@OldClassId)
  RAISERROR('DropClass left fixture registration.',16,10);
IF @@TRANCOUNT<>0 RAISERROR('Fixture client suite left a transaction.',16,10);
