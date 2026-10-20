IF OBJECT_ID('tSQLt.RegisterClassFixture') IS NOT NULL DROP PROCEDURE tSQLt.RegisterClassFixture;
IF OBJECT_ID('tSQLt.Private_RunClassFixture') IS NOT NULL DROP PROCEDURE tSQLt.Private_RunClassFixture;
IF OBJECT_ID('tSQLt.Private_ClassFixture') IS NOT NULL DROP TABLE tSQLt.Private_ClassFixture;
GO
---Build+
CREATE TABLE tSQLt.Private_ClassFixture
(
  ClassId INT NOT NULL PRIMARY KEY,
  SetUpObjectId INT NOT NULL
);
GO
CREATE PROCEDURE tSQLt.RegisterClassFixture
  @TestClassName NVARCHAR(MAX),
  @SetUpProcedure NVARCHAR(MAX)
AS
BEGIN
  DECLARE @ClassId INT=tSQLt.Private_GetSchemaId(@TestClassName),@SetUpId INT=OBJECT_ID(@SetUpProcedure,N'P');
  IF NOT EXISTS(SELECT 1 FROM tSQLt.TestClasses WHERE SchemaId=@ClassId)
  BEGIN
    RAISERROR('RegisterClassFixture requires a registered test class.',16,10);
    RETURN;
  END;
  IF @SetUpProcedure IS NOT NULL AND
    (PARSENAME(@SetUpProcedure,3) IS NOT NULL OR PARSENAME(@SetUpProcedure,4) IS NOT NULL
     OR NOT EXISTS(SELECT 1 FROM sys.procedures WHERE object_id=@SetUpId AND schema_id=@ClassId AND type=N'P')
     OR EXISTS(SELECT 1 FROM sys.parameters WHERE object_id=@SetUpId))
  BEGIN
    RAISERROR('ClassSetUp must be a parameterless SQL procedure in the test class.',16,10);
    RETURN;
  END;
  DELETE tSQLt.Private_ClassFixture WHERE ClassId=@ClassId;
  IF @SetUpProcedure IS NOT NULL INSERT tSQLt.Private_ClassFixture VALUES(@ClassId,@SetUpId);
END;
GO
-- The caller supplies the selected procedure order as XML. Case providers run
-- before the transaction and are expanded into a rollback-resistant table variable.
CREATE PROCEDURE tSQLt.Private_RunClassFixture
  @ClassName NVARCHAR(MAX),
  @Selected XML=NULL,
  @SingleTest NVARCHAR(MAX)=NULL,
  @CaseId NVARCHAR(MAX)=NULL,
  @ExecutedOrder XML=NULL OUTPUT
AS
BEGIN
  IF @@TRANCOUNT<>0 OR OBJECT_ID('tempdb..#tSQLt_ActiveFixture') IS NOT NULL
  BEGIN
    RAISERROR('Class fixtures require no caller transaction and do not allow nested runs.',16,10);
    RETURN;
  END;
  DECLARE @ClassId INT=tSQLt.Private_GetSchemaId(@ClassName),@ClassSetUp NVARCHAR(MAX),@SetUpId INT;
  SELECT @SetUpId=SetUpObjectId FROM tSQLt.Private_ClassFixture WHERE ClassId=@ClassId;
  IF NOT EXISTS(SELECT 1 FROM sys.procedures WHERE object_id=@SetUpId AND schema_id=@ClassId AND type=N'P')
     OR EXISTS(SELECT 1 FROM sys.parameters WHERE object_id=@SetUpId)
  BEGIN
    RAISERROR('The registered ClassSetUp no longer identifies a parameterless procedure in this class.',16,10);
    RETURN;
  END;
  SET @ClassSetUp=tSQLt.Private_GetQuotedFullName(@SetUpId);
  DECLARE @Tests TABLE(Ordinal INT,TestName NVARCHAR(517),ObjectId INT);
  IF @SingleTest IS NOT NULL
    INSERT @Tests VALUES(1,@SingleTest,OBJECT_ID(@SingleTest));
  ELSE IF @Selected IS NOT NULL
    INSERT @Tests
      SELECT T.N.value('@ordinal','INT'),QUOTENAME(SCHEMA_NAME(@ClassId))+N'.'+QUOTENAME(T.N.value('@name','NVARCHAR(128)')),
        OBJECT_ID(QUOTENAME(SCHEMA_NAME(@ClassId))+N'.'+QUOTENAME(T.N.value('@name','NVARCHAR(128)')))
      FROM @Selected.nodes('/TestOrder/Test') T(N);
  ELSE
    INSERT @Tests
      SELECT ROW_NUMBER() OVER(ORDER BY NEWID()),tSQLt.Private_GetQuotedFullName(object_id),object_id
      FROM sys.procedures WHERE schema_id=@ClassId AND LOWER(name) LIKE N'test%';
  IF EXISTS(SELECT 1 FROM @Tests T CROSS APPLY tSQLt.Private_ListTestAnnotations(T.ObjectId) A
             WHERE A.Annotation LIKE N'tSQLt.[[]@tSQLt:NoTransaction]%')
  BEGIN
    RAISERROR('Class fixtures cannot run a plan containing NoTransaction.',16,10);
    RETURN;
  END;
  DECLARE @Plan TABLE(Ordinal INT IDENTITY(1,1),TestName NVARCHAR(517),CaseId NVARCHAR(128),Ran BIT DEFAULT 0,
    DisplayName NVARCHAR(512),Result NVARCHAR(20),Msg NVARCHAR(MAX),Started DATETIME2,Ended DATETIME2);
  CREATE TABLE #tSQLt_CaseList(CaseId NVARCHAR(MAX),DisplayName NVARCHAR(MAX));
  -- Guard providers too: a nested public Run would clear the caller's results.
  CREATE TABLE #tSQLt_ActiveFixture(Active BIT);
  DECLARE @TestName NVARCHAR(517),@ObjectId INT,@RequestedCase BIT=0;
  DECLARE TestPlan CURSOR LOCAL FAST_FORWARD FOR SELECT TestName,ObjectId FROM @Tests ORDER BY Ordinal;
  OPEN TestPlan;
  FETCH NEXT FROM TestPlan INTO @TestName,@ObjectId;
  WHILE @@FETCH_STATUS=0
  BEGIN
    IF EXISTS(SELECT 1 FROM tSQLt.Private_CaseTest WHERE TestObjectId=@ObjectId)
    BEGIN
      DELETE #tSQLt_CaseList;
      EXEC tSQLt.Private_CollectCases @TestName;
      IF @CaseId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM #tSQLt_CaseList
          WHERE DATALENGTH(CaseId)=DATALENGTH(@CaseId) AND CONVERT(VARBINARY(256),CaseId)=CONVERT(VARBINARY(256),@CaseId))
      BEGIN
        CLOSE TestPlan; DEALLOCATE TestPlan;
        RAISERROR('The requested CaseId does not exist.',16,10);
        RETURN;
      END;
      INSERT @Plan(TestName,CaseId,DisplayName)
        SELECT @TestName,CaseId,DisplayName FROM #tSQLt_CaseList
        WHERE @CaseId IS NULL OR (DATALENGTH(CaseId)=DATALENGTH(@CaseId)
          AND CONVERT(VARBINARY(256),CaseId)=CONVERT(VARBINARY(256),@CaseId))
        ORDER BY CONVERT(VARBINARY(256),CaseId);
    END;
    ELSE INSERT @Plan(TestName) VALUES(@TestName);
    FETCH NEXT FROM TestPlan INTO @TestName,@ObjectId;
  END;
  CLOSE TestPlan; DEALLOCATE TestPlan;
  IF NOT EXISTS(SELECT 1 FROM @Plan) RETURN;

  -- Preserve results from earlier classes even if hostile test SQL commits or
  -- rolls back the fixture transaction. This buffer is never a transactional table.
  DECLARE @Previous TABLE(Id INT,Class NVARCHAR(MAX),TestCase NVARCHAR(MAX),TranName NVARCHAR(MAX),
    Result NVARCHAR(MAX),Msg NVARCHAR(MAX),TestStartTime DATETIME2,TestEndTime DATETIME2,
    CaseId NVARCHAR(128),CaseDisplayName NVARCHAR(512),CaseState NVARCHAR(20),CaseExecutionMode NVARCHAR(20));
  INSERT @Previous SELECT Id,Class,TestCase,TranName,Result,Msg,TestStartTime,TestEndTime,
    CaseId,CaseDisplayName,CaseState,CaseExecutionMode FROM tSQLt.TestResult;
  DECLARE @SetUp NVARCHAR(MAX),@CleanUp NVARCHAR(MAX),@TransactionId BIGINT,
    @Broken NVARCHAR(MAX),@Result NVARCHAR(MAX),@Msg NVARCHAR(MAX),@Started DATETIME2,@Ended DATETIME2,
    @Index INT=1,@Id NVARCHAR(128),@ResultId INT,@Entry XML;
  EXEC tSQLt.Private_GetClassHelperProcedureName @ClassId,@SetUp OUTPUT,@CleanUp OUTPUT;
  SELECT @ExecutedOrder=(SELECT 1 AS [@version],SCHEMA_NAME(@ClassId) AS [@class] FOR XML PATH('TestOrder'),TYPE);
  BEGIN TRY
    BEGIN TRAN;
    SELECT @TransactionId=transaction_id FROM sys.dm_tran_current_transaction;
    EXEC @ClassSetUp;
    IF @@TRANCOUNT<>1 OR XACT_STATE()<>1
       OR NOT EXISTS(SELECT 1 FROM sys.dm_tran_current_transaction WHERE transaction_id=@TransactionId)
      SET @Broken=N'ClassSetUp changed or invalidated the fixture transaction.';
  END TRY
  BEGIN CATCH
    SET @Broken=N'ClassSetUp failed: '+ERROR_MESSAGE();
  END CATCH;
  WHILE EXISTS(SELECT 1 FROM @Plan WHERE Ordinal=@Index)
  BEGIN
    SELECT @TestName=TestName,@Id=CaseId FROM @Plan WHERE Ordinal=@Index;
    SELECT @Result=NULL,@Msg=NULL,@Started=SYSDATETIME(),@Ended=NULL,@ResultId=NULL;
    IF @Broken IS NULL
    BEGIN
      UPDATE @Plan SET Ran=1 WHERE Ordinal=@Index;
      -- Record procedures once, in the same order used by execution-order replay.
      IF NOT EXISTS(SELECT 1 FROM @Plan WHERE Ordinal<@Index AND TestName=@TestName)
      BEGIN
        SELECT @Entry=(SELECT 1+(SELECT COUNT(DISTINCT TestName) FROM @Plan WHERE Ordinal<@Index) AS [@ordinal],
          OBJECT_NAME(OBJECT_ID(@TestName)) AS [@name] FOR XML PATH('Test'),TYPE);
        SET @ExecutedOrder.modify('insert sql:variable("@Entry") as last into (/TestOrder)[1]');
      END;
      BEGIN TRY
        IF @Id IS NOT NULL
        BEGIN
          INSERT tSQLt.TestResult(Class,TestCase,CaseId,CaseDisplayName,Result)
            SELECT SCHEMA_NAME(@ClassId),OBJECT_NAME(OBJECT_ID(@TestName)),CaseId,DisplayName,N'Running'
            FROM @Plan WHERE Ordinal=@Index;
          SET @ResultId=SCOPE_IDENTITY();
        END;
        EXEC tSQLt.Private_RunTest @TestName,@SetUp,@CleanUp,@CaseId=@Id,@CaseResultId=@ResultId,
          @FixtureResult=@Result OUTPUT,@FixtureMessage=@Msg OUTPUT,
          @FixtureStart=@Started OUTPUT,@FixtureEnd=@Ended OUTPUT;
      END TRY
      BEGIN CATCH
        SELECT @Result=N'Error',@Msg=ERROR_MESSAGE(),@Ended=SYSDATETIME();
      END CATCH;
      IF @@TRANCOUNT<>1 OR XACT_STATE()<>1
         OR NOT EXISTS(SELECT 1 FROM sys.dm_tran_current_transaction WHERE transaction_id=@TransactionId)
        SET @Broken=N'Test lost or invalidated the class fixture transaction; remaining tests were not run.';
    END;
    IF @Broken IS NOT NULL SELECT @Result=N'Error',@Msg=@Broken,@Ended=SYSDATETIME();
    UPDATE @Plan SET Result=ISNULL(@Result,N'Error'),Msg=@Msg,Started=@Started,Ended=ISNULL(@Ended,SYSDATETIME())
      WHERE Ordinal=@Index;
    SET @Index=@Index+1;
  END;
  IF @@TRANCOUNT>0 ROLLBACK;
  DELETE tSQLt.TestResult;
  SET IDENTITY_INSERT tSQLt.TestResult ON;
  INSERT tSQLt.TestResult(Id,Class,TestCase,TranName,Result,Msg,TestStartTime,TestEndTime,
    CaseId,CaseDisplayName,CaseState,CaseExecutionMode) SELECT * FROM @Previous;
  SET IDENTITY_INSERT tSQLt.TestResult OFF;
  INSERT tSQLt.TestResult(Class,TestCase,Result,Msg,TestStartTime,TestEndTime,
    CaseId,CaseDisplayName,CaseState,CaseExecutionMode)
    SELECT SCHEMA_NAME(@ClassId),PARSENAME(TestName,1),Result,Msg,Started,Ended,CaseId,DisplayName,
      CASE WHEN CaseId IS NOT NULL THEN CASE WHEN Ran=0 THEN N'NotRun' ELSE N'Completed' END END,
      CASE WHEN CaseId IS NOT NULL THEN N'Independent' END
    FROM @Plan ORDER BY Ordinal;
END;
GO
---Build-
