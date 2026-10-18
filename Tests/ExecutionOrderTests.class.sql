EXEC tSQLt.NewTestClass 'ExecutionOrderTests';
GO
CREATE PROCEDURE ExecutionOrderTests.SetUp
AS
BEGIN
  EXEC('CREATE SCHEMA OrderInner;');
  EXEC('CREATE PROCEDURE OrderInner.[test A] AS RETURN;');
  EXEC('CREATE PROCEDURE OrderInner.[test B] AS RETURN;');
  EXEC('CREATE PROCEDURE OrderInner.[test C] AS RETURN;');
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_OutputTestResults';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.AssertRejected
  @Order XML
AS
BEGIN
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest';
  DECLARE @Caught BIT = 0;
  BEGIN TRY
    EXEC tSQLt.Run 'OrderInner', @TestOrder = @Order;
  END TRY
  BEGIN CATCH
    SET @Caught = 1;
  END CATCH;
  EXEC tSQLt.AssertEquals 1, @Caught, 'Expected rejection before any test executes.';
  EXEC tSQLt.AssertEmptyTable 'tSQLt.Private_RunTest_SpyProcedureLog';
  EXEC tSQLt.AssertEmptyTable 'tSQLt.Private_OutputTestResults_SpyProcedureLog';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test fixed seeds have stable expected orders]
AS
BEGIN
  DECLARE @Order XML;
  EXEC tSQLt.Run 'OrderInner', @Seed = 0, @ExecutedOrder = @Order OUTPUT;
  DECLARE @Actual NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX),@Order);
  EXEC tSQLt.AssertEqualsString N'<TestOrder version="1" class="OrderInner"><Test ordinal="1" name="test A"/><Test ordinal="2" name="test C"/><Test ordinal="3" name="test B"/></TestOrder>', @Actual;
  EXEC tSQLt.Run 'OrderInner', @Seed = -2147483648, @ExecutedOrder = @Order OUTPUT;
  SET @Actual = CONVERT(NVARCHAR(MAX),@Order);
  EXEC tSQLt.AssertEqualsString N'<TestOrder version="1" class="OrderInner"><Test ordinal="1" name="test B"/><Test ordinal="2" name="test C"/><Test ordinal="3" name="test A"/></TestOrder>', @Actual;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test seed is independent of procedure object ids]
AS
BEGIN
  DECLARE @Before XML, @After XML;
  EXEC tSQLt.Run 'OrderInner', @Seed = 12345, @ExecutedOrder = @Before OUTPUT;
  DROP PROCEDURE OrderInner.[test A];
  EXEC('CREATE PROCEDURE OrderInner.[test A] AS RETURN;');
  EXEC tSQLt.Run 'OrderInner', @Seed = 12345, @ExecutedOrder = @After OUTPUT;
  DECLARE @Expected NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX),@Before), @Actual NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX),@After);
  EXEC tSQLt.AssertEqualsString @Expected, @Actual;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test recorded order matches actual dispatch order]
AS
BEGIN
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest';
  DECLARE @Order XML;
  EXEC tSQLt.Run 'OrderInner', @Seed = 12345, @ExecutedOrder = @Order OUTPUT;
  SELECT _id_ AS Ordinal, TestName INTO #Actual FROM tSQLt.Private_RunTest_SpyProcedureLog;
  SELECT T.N.value('@ordinal','INT') AS Ordinal,
         N'[OrderInner].'+QUOTENAME(T.N.value('@name','NVARCHAR(128)')) AS TestName
    INTO #Expected FROM @Order.nodes('/TestOrder/Test') T(N);
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test capture without seed returns an entire class]
AS
BEGIN
  DECLARE @Order XML;
  EXEC tSQLt.Run 'OrderInner', @ExecutedOrder = @Order OUTPUT;
  DECLARE @Count INT = @Order.value('count(/TestOrder/Test)','INT');
  EXEC tSQLt.AssertEquals 3,@Count;
  DECLARE @Again XML;
  EXEC tSQLt.Run 'OrderInner', @TestOrder = @Order, @ExecutedOrder = @Again OUTPUT;
  DECLARE @Expected NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX),@Order), @Actual NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX),@Again);
  EXEC tSQLt.AssertEqualsString @Expected,@Actual;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test replay follows explicit ordinals and ignores added tests]
AS
BEGIN
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest';
  EXEC('CREATE PROCEDURE OrderInner.[test added] AS RETURN;');
  DECLARE @Order XML = N'<TestOrder version="1" class="OrderInner"><Test ordinal="2" name="test A"/><Test ordinal="1" name="test C"/></TestOrder>';
  EXEC tSQLt.Run 'OrderInner', @TestOrder = @Order;
  SELECT _id_ AS Ordinal, TestName INTO #Actual FROM tSQLt.Private_RunTest_SpyProcedureLog;
  SELECT TOP(0) Ordinal+0 AS Ordinal, TestName INTO #Expected FROM #Actual;
  INSERT #Expected VALUES(1,N'[OrderInner].[test C]'),(2,N'[OrderInner].[test A]');
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test empty order executes no tests]
AS
BEGIN
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest';
  DECLARE @Order XML;
  EXEC tSQLt.Run 'OrderInner', @TestOrder = N'<TestOrder version="1" class="OrderInner"/>', @ExecutedOrder = @Order OUTPUT;
  EXEC tSQLt.AssertEmptyTable 'tSQLt.Private_RunTest_SpyProcedureLog';
  DECLARE @Actual NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX),@Order);
  EXEC tSQLt.AssertEqualsString N'<TestOrder version="1" class="OrderInner"/>', @Actual;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test empty class produces an empty record]
AS
BEGIN
  EXEC('CREATE SCHEMA EmptyOrderClass;');
  DECLARE @Order XML;
  EXEC tSQLt.Run 'EmptyOrderClass', @Seed = 1, @ExecutedOrder = @Order OUTPUT;
  DECLARE @Actual NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX),@Order);
  EXEC tSQLt.AssertEqualsString N'<TestOrder version="1" class="EmptyOrderClass"/>', @Actual;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects deleted or renamed tests before executing valid entries]
AS
BEGIN
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="1" class="OrderInner"><Test ordinal="1" name="test A"/><Test ordinal="2" name="test missing"/></TestOrder>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects duplicate tests]
AS
BEGIN
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="1" class="OrderInner"><Test ordinal="1" name="test A"/><Test ordinal="2" name="test A"/></TestOrder>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects duplicate ordinals]
AS
BEGIN
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="1" class="OrderInner"><Test ordinal="1" name="test A"/><Test ordinal="1" name="test B"/></TestOrder>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects gaps in ordinals]
AS
BEGIN
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="1" class="OrderInner"><Test ordinal="2" name="test A"/></TestOrder>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects nonpositive ordinals]
AS
BEGIN
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="1" class="OrderInner"><Test ordinal="0" name="test A"/></TestOrder>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects noninteger ordinals]
AS
BEGIN
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="1" class="OrderInner"><Test ordinal="abc" name="test A"/></TestOrder>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects incorrect class]
AS
BEGIN
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="1" class="OtherClass"><Test ordinal="1" name="test A"/></TestOrder>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects overlong names instead of executing a truncated name]
AS
BEGIN
  DECLARE @Name NVARCHAR(128) = N'test'+REPLICATE(N'a',124);
  DECLARE @Command NVARCHAR(MAX) = N'CREATE PROCEDURE OrderInner.'+QUOTENAME(@Name)+N' AS RETURN;';
  EXEC(@Command);
  DECLARE @Order XML = (SELECT 1 AS [@version],N'OrderInner' AS [@class],
      (SELECT 1 AS [@ordinal],@Name+N'x' AS [@name] FOR XML PATH('Test'),TYPE)
    FOR XML PATH('TestOrder'),TYPE);
  EXEC ExecutionOrderTests.AssertRejected @Order;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects unknown version]
AS
BEGIN
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="2" class="OrderInner"/>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects multiple roots]
AS
BEGIN
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="1" class="OrderInner"/><TestOrder version="1" class="OrderInner"/>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects unexpected elements]
AS
BEGIN
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="1" class="OrderInner"><Typo ordinal="1" name="test A"/></TestOrder>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects missing attributes]
AS
BEGIN
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="1" class="OrderInner"><Test name="test A"/></TestOrder>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects setup as a replay target]
AS
BEGIN
  EXEC('CREATE PROCEDURE OrderInner.SetUp AS RETURN;');
  EXEC ExecutionOrderTests.AssertRejected N'<TestOrder version="1" class="OrderInner"><Test ordinal="1" name="SetUp"/></TestOrder>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects seed combined with replay]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessage = 'Execution order requires an explicit test class and cannot combine @Seed with @TestOrder.';
  EXEC tSQLt.Run 'OrderInner', @Seed = 1, @TestOrder = N'<TestOrder version="1" class="OrderInner"/>';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects an omitted class even when a last class exists]
AS
BEGIN
  EXEC tSQLt.Run 'OrderInner';
  EXEC tSQLt.ExpectException @ExpectedMessage = 'Execution order requires an explicit test class and cannot combine @Seed with @TestOrder.';
  EXEC tSQLt.Run @Seed = 1;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects single test with seed]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessage = 'Execution order requires an explicit test class.';
  EXEC tSQLt.Run 'OrderInner.[test A]', @Seed = 1;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects blank class instead of reusing the last class]
AS
BEGIN
  EXEC tSQLt.Run 'OrderInner';
  EXEC tSQLt.ExpectException @ExpectedMessage = 'Execution order requires an explicit test class and cannot combine @Seed with @TestOrder.';
  EXEC tSQLt.Run N'   ', @Seed = 1;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test rejects single test with capture only]
AS
BEGIN
  DECLARE @Order XML;
  EXEC tSQLt.ExpectException @ExpectedMessage = 'Execution order requires an explicit test class.';
  EXEC tSQLt.Run 'OrderInner.[test A]', @ExecutedOrder = @Order OUTPUT;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test quotes Unicode and punctuation in class and procedure names]
AS
BEGIN
  EXEC(N'CREATE SCHEMA [順序 '' ]]];');
  EXEC(N'CREATE PROCEDURE [順序 '' ]]].[test 日本語 '' & < ]]] AS RETURN;');
  DECLARE @Before XML, @After XML;
  EXEC tSQLt.Run N'[順序 '' ]]]', @Seed = 42, @ExecutedOrder = @Before OUTPUT;
  EXEC tSQLt.Run N'[順序 '' ]]]', @TestOrder = @Before, @ExecutedOrder = @After OUTPUT;
  DECLARE @Expected NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX),@Before), @Actual NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX),@After);
  EXEC tSQLt.AssertEqualsString @Expected,@Actual;
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Success');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test runs setup independently for every transactional test]
AS
BEGIN
  EXEC('CREATE TABLE OrderInner.SetupLog(Value INT);');
  EXEC('CREATE PROCEDURE OrderInner.SetUp AS INSERT OrderInner.SetupLog VALUES(1);');
  EXEC('ALTER PROCEDURE OrderInner.[test A] AS BEGIN DECLARE @n INT = (SELECT COUNT(*) FROM OrderInner.SetupLog); EXEC tSQLt.AssertEquals 1,@n; END;');
  EXEC('ALTER PROCEDURE OrderInner.[test B] AS BEGIN DECLARE @n INT = (SELECT COUNT(*) FROM OrderInner.SetupLog); EXEC tSQLt.AssertEquals 1,@n; END;');
  EXEC tSQLt.Run 'OrderInner', @Seed = 1;
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Success');
  EXEC tSQLt.AssertEquals 3,@Count;
  EXEC tSQLt.AssertEmptyTable 'OrderInner.SetupLog';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test records skip failure expected exception and following tests]
AS
BEGIN
  EXEC('--[@'+'tSQLt:SkipTest](''skip'')
    ALTER PROCEDURE OrderInner.[test A] AS EXEC tSQLt.Fail ''must not run'';');
  EXEC('ALTER PROCEDURE OrderInner.[test B] AS EXEC tSQLt.Fail ''failure'';');
  EXEC('ALTER PROCEDURE OrderInner.[test C] AS BEGIN EXEC tSQLt.ExpectException @ExpectedMessage = ''expected''; RAISERROR(''expected'',16,10); END;');
  DECLARE @Order XML;
  EXEC tSQLt.Run 'OrderInner', @Seed = 12345, @ExecutedOrder = @Order OUTPUT;
  SELECT TestCase,Result INTO #Actual FROM tSQLt.TestResult;
  SELECT TOP(0) * INTO #Expected FROM #Actual;
  INSERT #Expected VALUES('test A','Skipped'),('test B','Failure'),('test C','Success');
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
  DECLARE @Count INT = @Order.value('count(/TestOrder/Test)','INT');
  EXEC tSQLt.AssertEquals 3,@Count;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test setup errors retain a record and do not prevent later tests]
AS
BEGIN
  EXEC('CREATE PROCEDURE OrderInner.SetUp AS RAISERROR(''setup error'',16,10);');
  DECLARE @Order XML;
  EXEC tSQLt.Run 'OrderInner', @Seed = 1, @ExecutedOrder = @Order OUTPUT;
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.TestResult WHERE Result = 'Error');
  EXEC tSQLt.AssertEquals 3,@Count;
  SET @Count = @Order.value('count(/TestOrder/Test)','INT');
  EXEC tSQLt.AssertEquals 3,@Count;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test nested runs cannot replace the outer record]
AS
BEGIN
  EXEC('CREATE SCHEMA NestedOrderClass;');
  EXEC('CREATE PROCEDURE NestedOrderClass.[test nested] AS RETURN;');
  EXEC('ALTER PROCEDURE OrderInner.[test A] AS BEGIN DECLARE @Inner XML; EXEC tSQLt.Run ''NestedOrderClass'', @Seed=4, @ExecutedOrder=@Inner OUTPUT; END;');
  DECLARE @Order XML;
  EXEC tSQLt.Run 'OrderInner', @Seed=0, @ExecutedOrder=@Order OUTPUT;
  DECLARE @Actual NVARCHAR(MAX) = CONVERT(NVARCHAR(MAX),@Order);
  EXEC tSQLt.AssertEqualsString N'<TestOrder version="1" class="OrderInner"><Test ordinal="1" name="test A"/><Test ordinal="2" name="test C"/><Test ordinal="3" name="test B"/></TestOrder>',@Actual;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test class setup and cleanup names are forwarded unchanged]
AS
BEGIN
  EXEC('CREATE PROCEDURE OrderInner.SetUp AS RETURN;');
  EXEC('CREATE PROCEDURE OrderInner.CleanUp AS RETURN;');
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest';
  EXEC tSQLt.Run 'OrderInner', @Seed = 1;
  SELECT DISTINCT SetUp,CleanUp INTO #Actual FROM tSQLt.Private_RunTest_SpyProcedureLog;
  SELECT TOP(0) * INTO #Expected FROM #Actual;
  INSERT #Expected VALUES('[OrderInner].[SetUp]','[OrderInner].[CleanUp]');
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test runtime abort stops dispatch and retains the error]
AS
BEGIN
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest',
    @CommandToExecute = N'IF @TestName = N''[OrderInner].[test B]'' RAISERROR(''stop execution'',16,10);';
  DECLARE @Order XML = N'<TestOrder version="1" class="OrderInner"><Test ordinal="1" name="test A"/><Test ordinal="2" name="test B"/><Test ordinal="3" name="test C"/></TestOrder>';
  DECLARE @Caught NVARCHAR(MAX);
  BEGIN TRY
    EXEC tSQLt.Run 'OrderInner', @TestOrder = @Order;
  END TRY
  BEGIN CATCH
    SET @Caught = ERROR_MESSAGE();
  END CATCH;
  EXEC tSQLt.AssertEqualsString N'stop execution',@Caught;
  DECLARE @Count INT = (SELECT COUNT(*) FROM tSQLt.Private_RunTest_SpyProcedureLog);
  EXEC tSQLt.AssertEquals 2,@Count;
  SET @Count = (SELECT COUNT(*) FROM tSQLt.Private_OutputTestResults_SpyProcedureLog);
  EXEC tSQLt.AssertEquals 1,@Count,'Expected the results of the tests that ran before the abort to be output.';
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test runtime abort error is retained over a formatter error]
AS
BEGIN
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest',
    @CommandToExecute = N'IF @TestName = N''[OrderInner].[test B]'' RAISERROR(''stop execution'',16,10);';
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_OutputTestResults', @CommandToExecute = N'RAISERROR(''formatter error'',16,10);';
  DECLARE @Order XML = N'<TestOrder version="1" class="OrderInner"><Test ordinal="1" name="test A"/><Test ordinal="2" name="test B"/><Test ordinal="3" name="test C"/></TestOrder>';
  DECLARE @Caught NVARCHAR(MAX);
  BEGIN TRY
    EXEC tSQLt.Run 'OrderInner', @TestOrder = @Order;
  END TRY
  BEGIN CATCH
    SET @Caught = ERROR_MESSAGE();
  END CATCH;
  EXEC tSQLt.AssertEqualsString N'stop execution',@Caught;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test formatter errors retain the error]
AS
BEGIN
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_RunTest';
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_OutputTestResults', @CommandToExecute = N'RAISERROR(''formatter error'',16,10);';
  DECLARE @Caught NVARCHAR(MAX);
  BEGIN TRY
    EXEC tSQLt.Run 'OrderInner', @Seed = 0;
  END TRY
  BEGIN CATCH
    SET @Caught = ERROR_MESSAGE();
  END CATCH;
  EXEC tSQLt.AssertEqualsString N'formatter error',@Caught;
END;
GO
CREATE PROCEDURE ExecutionOrderTests.[test NoTransaction cleanup executes with the original transaction count]
AS
BEGIN
  CREATE TABLE #Lifecycle(Phase NVARCHAR(20), TranCount INT);
  -- Measure with the same INSERT context used by the lifecycle procedures.
  INSERT #Lifecycle VALUES('before',@@TRANCOUNT);
  DECLARE @Before INT = (SELECT TranCount FROM #Lifecycle);
  DELETE #Lifecycle;
  EXEC('CREATE PROCEDURE OrderInner.SetUp AS INSERT #Lifecycle VALUES(''setup'',@@TRANCOUNT);');
  EXEC('CREATE PROCEDURE OrderInner.CleanUp AS INSERT #Lifecycle VALUES(''cleanup'',@@TRANCOUNT);');
  DROP PROCEDURE OrderInner.[test A];
  EXEC('--[@'+'tSQLt:NoTransaction](DEFAULT)
    CREATE PROCEDURE OrderInner.[test A] AS INSERT #Lifecycle VALUES(''body'',@@TRANCOUNT);');
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_NoTransactionHandleTables';
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_CleanUp';
  EXEC tSQLt.SpyProcedure 'tSQLt.Private_AssertNoSideEffects';
  DECLARE @Order XML;
  EXEC tSQLt.Run 'OrderInner', @TestResultFormatter = 'tSQLt.NullTestResultFormatter', @TestOrder = N'<TestOrder version="1" class="OrderInner"><Test ordinal="1" name="test A"/></TestOrder>', @ExecutedOrder = @Order OUTPUT;
  SELECT Phase, TranCount INTO #Actual FROM #Lifecycle;
  SELECT TOP(0) * INTO #Expected FROM #Actual;
  INSERT #Expected VALUES('setup',@Before),('body',@Before),('cleanup',@Before);
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
  DECLARE @Count INT = @Order.value('count(/TestOrder/Test)','INT');
  EXEC tSQLt.AssertEquals 1,@Count;
END;
GO
