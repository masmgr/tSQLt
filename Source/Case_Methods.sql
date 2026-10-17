IF OBJECT_ID('tSQLt.RegisterCaseTest') IS NOT NULL DROP PROCEDURE tSQLt.RegisterCaseTest;
IF OBJECT_ID('tSQLt.ListCases') IS NOT NULL DROP PROCEDURE tSQLt.ListCases;
IF OBJECT_ID('tSQLt.Private_CollectCases') IS NOT NULL DROP PROCEDURE tSQLt.Private_CollectCases;
IF OBJECT_ID('tSQLt.Private_RunCases') IS NOT NULL DROP PROCEDURE tSQLt.Private_RunCases;
IF OBJECT_ID('tSQLt.CaseXmlResultFormatter') IS NOT NULL DROP PROCEDURE tSQLt.CaseXmlResultFormatter;
IF OBJECT_ID('tSQLt.ReportCaseResults') IS NOT NULL DROP PROCEDURE tSQLt.ReportCaseResults;
IF OBJECT_ID('tSQLt.Private_CaseTest') IS NOT NULL DROP TABLE tSQLt.Private_CaseTest;
GO
---Build+
CREATE TABLE tSQLt.Private_CaseTest
(
  TestObjectId INT NOT NULL PRIMARY KEY,
  CaseProviderObjectId INT NOT NULL
);
GO
CREATE PROCEDURE tSQLt.RegisterCaseTest
  @TestName NVARCHAR(MAX),
  @CaseProvider NVARCHAR(MAX)
AS
BEGIN
  DECLARE @TestId INT = OBJECT_ID(@TestName, 'P');
  DECLARE @ProviderId INT = OBJECT_ID(@CaseProvider, 'P');
  IF @TestId IS NULL OR @ProviderId IS NULL OR @TestId = @ProviderId
  BEGIN
    RAISERROR('TestName and CaseProvider must identify distinct SQL procedures in the current database.',16,10);
    RETURN;
  END;
  IF NOT EXISTS(SELECT 1 FROM sys.parameters WHERE object_id = @TestId AND name = '@CaseId'
                  AND system_type_id = TYPE_ID('nvarchar') AND max_length = 256 AND is_output = 0)
  BEGIN
    RAISERROR('A case test must accept @CaseId NVARCHAR(128).',16,10);
    RETURN;
  END;
  DELETE FROM tSQLt.Private_CaseTest WHERE TestObjectId = @TestId;
  INSERT tSQLt.Private_CaseTest VALUES(@TestId, @ProviderId);
END;
GO
-- Both callers own #tSQLt_CaseList. Providers insert into it and return no result sets.
CREATE PROCEDURE tSQLt.Private_CollectCases @TestName NVARCHAR(MAX), @CaseProvider NVARCHAR(MAX) = NULL
AS
BEGIN
  DECLARE @Provider NVARCHAR(MAX);
  SELECT @Provider = tSQLt.Private_GetQuotedFullName(CaseProviderObjectId)
    FROM tSQLt.Private_CaseTest
   WHERE TestObjectId = OBJECT_ID(@TestName);
  IF @CaseProvider IS NOT NULL
    SET @Provider = tSQLt.Private_GetQuotedFullName(OBJECT_ID(@CaseProvider,'P'));
  IF @Provider IS NULL OR OBJECT_ID(@Provider, 'P') IS NULL
  BEGIN
    RAISERROR('No case provider is registered or the registered provider no longer exists.',16,10);
    RETURN;
  END;
  EXEC @Provider;
  IF NOT EXISTS(SELECT 1 FROM #tSQLt_CaseList)
    RAISERROR('The case provider returned no cases.',16,10);
  IF EXISTS(SELECT 1 FROM #tSQLt_CaseList WHERE CaseId IS NULL OR DATALENGTH(CaseId) = 0
              OR DATALENGTH(CaseId) > 256 OR DisplayName IS NULL OR DATALENGTH(DisplayName) = 0
              OR DATALENGTH(DisplayName) > 1024)
    RAISERROR('Cases require a nonempty CaseId (at most 128 UTF-16 units) and DisplayName (at most 512 UTF-16 units).',16,10);
  IF EXISTS(SELECT 1 FROM #tSQLt_CaseList GROUP BY DATALENGTH(CaseId),CONVERT(VARBINARY(256),CaseId) HAVING COUNT(*) > 1)
    RAISERROR('The case provider returned duplicate CaseId values.',16,10);
END;
GO
CREATE PROCEDURE tSQLt.ListCases @TestName NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;
  CREATE TABLE #tSQLt_CaseList(CaseId NVARCHAR(MAX), DisplayName NVARCHAR(MAX));
  BEGIN TRY
    EXEC tSQLt.Private_CollectCases @TestName;
    SELECT tSQLt.Private_GetQuotedFullName(OBJECT_ID(@TestName)) AS TestName,
           CaseId, DisplayName, CAST('Independent' AS NVARCHAR(20)) AS ExecutionMode
      FROM #tSQLt_CaseList ORDER BY CONVERT(VARBINARY(256),CaseId);
  END TRY
  BEGIN CATCH
    DECLARE @Message NVARCHAR(MAX) = ERROR_MESSAGE();
    RAISERROR('%s',16,10,@Message);
    RETURN;
  END CATCH;
END;
GO
CREATE PROCEDURE tSQLt.Private_RunCases
  @TestName NVARCHAR(MAX),
  @SetUp NVARCHAR(MAX) = NULL,
  @CleanUp NVARCHAR(MAX) = NULL,
  @CaseId NVARCHAR(MAX) = NULL
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @Class NVARCHAR(MAX) = OBJECT_SCHEMA_NAME(OBJECT_ID(@TestName));
  DECLARE @TestCase NVARCHAR(MAX) = OBJECT_NAME(OBJECT_ID(@TestName));
  CREATE TABLE #tSQLt_CaseList(CaseId NVARCHAR(MAX), DisplayName NVARCHAR(MAX));
  BEGIN TRY
    EXEC tSQLt.Private_CollectCases @TestName;
    IF @CaseId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM #tSQLt_CaseList
         WHERE DATALENGTH(CaseId) = DATALENGTH(@CaseId) AND CONVERT(VARBINARY(256),CaseId) = CONVERT(VARBINARY(256),@CaseId))
      RAISERROR('The requested CaseId does not exist.',16,10);
  END TRY
  BEGIN CATCH
    INSERT tSQLt.TestResult(Class,TestCase,Result,Msg,TestEndTime)
      VALUES(@Class,@TestCase,'Error',ERROR_MESSAGE(),SYSDATETIME());
    RETURN;
  END CATCH;

  DECLARE @Plan TABLE(CaseId NVARCHAR(128), DisplayName NVARCHAR(512), ResultId INT, Done BIT DEFAULT 0);
  INSERT @Plan(CaseId,DisplayName)
    SELECT CaseId,DisplayName FROM #tSQLt_CaseList
     WHERE @CaseId IS NULL OR (DATALENGTH(CaseId) = DATALENGTH(@CaseId) AND CONVERT(VARBINARY(256),CaseId) = CONVERT(VARBINARY(256),@CaseId));
  DECLARE @Id NVARCHAR(128), @Display NVARCHAR(512), @ResultId INT;
  -- Materialize every expected outcome before starting any case transaction.
  WHILE EXISTS(SELECT 1 FROM @Plan WHERE ResultId IS NULL)
  BEGIN
    SELECT TOP(1) @Id = CaseId, @Display = DisplayName FROM @Plan WHERE ResultId IS NULL
     ORDER BY CONVERT(VARBINARY(256),CaseId);
    INSERT tSQLt.TestResult(Class,TestCase,Result,Msg,CaseId,CaseDisplayName,CaseState,CaseExecutionMode)
      VALUES(@Class,@TestCase,'Error','Case was not executed.',@Id,@Display,'NotRun','Independent');
    SET @ResultId = SCOPE_IDENTITY();
    UPDATE @Plan SET ResultId = @ResultId WHERE DATALENGTH(CaseId) = DATALENGTH(@Id) AND CONVERT(VARBINARY(256),CaseId) = CONVERT(VARBINARY(256),@Id);
  END;
  WHILE EXISTS(SELECT 1 FROM @Plan WHERE Done = 0)
  BEGIN
    SELECT TOP(1) @Id = CaseId, @ResultId = ResultId FROM @Plan WHERE Done = 0
     ORDER BY CONVERT(VARBINARY(256),CaseId);
    -- Fatal isolation failures deliberately escape: remaining planned cases stay NotRun/Error.
    EXEC tSQLt.Private_RunTest @TestName, @SetUp, @CleanUp, @CaseId = @Id, @CaseResultId = @ResultId;
    UPDATE @Plan SET Done = 1 WHERE ResultId = @ResultId;
  END;
  IF EXISTS(SELECT 1 FROM @Plan P LEFT JOIN tSQLt.TestResult R ON P.ResultId = R.Id
              WHERE R.Id IS NULL OR ISNULL(R.CaseState,'') <> 'Completed'
                 OR R.Result IS NULL OR R.Result NOT IN ('Success','Failure','Error','Skipped')
                 OR R.CaseId IS NULL OR DATALENGTH(R.CaseId) <> DATALENGTH(P.CaseId)
                 OR CONVERT(VARBINARY(256),R.CaseId) <> CONVERT(VARBINARY(256),P.CaseId))
     OR EXISTS(SELECT 1 FROM tSQLt.TestResult R LEFT JOIN @Plan P ON P.ResultId = R.Id
                WHERE R.Id >= (SELECT MIN(ResultId) FROM @Plan) AND R.Class = @Class
                  AND R.TestCase = @TestCase AND P.ResultId IS NULL)
  BEGIN
    INSERT tSQLt.TestResult(Class,TestCase,Result,Msg,TestEndTime)
      VALUES(@Class,@TestCase,'Error','Planned cases and execution results do not match.',SYSDATETIME());
  END;
END;
GO
-- Adapter boundary for bulk calculations. No case body, setup, cleanup or isolation is run.
-- The caller supplies #tSQLt_CaseResults(CaseId NVARCHAR(MAX), Result NVARCHAR(MAX), Msg NVARCHAR(MAX)).
CREATE PROCEDURE tSQLt.ReportCaseResults
  @TestName NVARCHAR(MAX),
  @CaseProvider NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;
  IF OBJECT_ID(@TestName,'P') IS NULL
  BEGIN
    RAISERROR('TestName must identify a SQL procedure in the current database.',16,10);
    RETURN;
  END;
  DECLARE @Class NVARCHAR(MAX) = OBJECT_SCHEMA_NAME(OBJECT_ID(@TestName));
  DECLARE @TestCase NVARCHAR(MAX) = OBJECT_NAME(OBJECT_ID(@TestName));
  CREATE TABLE #tSQLt_CaseList(CaseId NVARCHAR(MAX), DisplayName NVARCHAR(MAX));
  BEGIN TRY
    EXEC tSQLt.Private_CollectCases @TestName, @CaseProvider;
    IF EXISTS(SELECT 1 FROM #tSQLt_CaseResults R WHERE NOT EXISTS
                (SELECT 1 FROM #tSQLt_CaseList P WHERE DATALENGTH(R.CaseId) = DATALENGTH(P.CaseId)
                  AND CONVERT(VARBINARY(MAX),R.CaseId) = CONVERT(VARBINARY(MAX),P.CaseId)))
      RAISERROR('Reported results contain an unplanned CaseId.',16,10);
    IF EXISTS(SELECT 1 FROM #tSQLt_CaseResults GROUP BY DATALENGTH(CaseId),CONVERT(VARBINARY(MAX),CaseId) HAVING COUNT(*) > 1)
      RAISERROR('Reported results contain duplicate CaseId values.',16,10);
    IF EXISTS(SELECT 1 FROM #tSQLt_CaseResults WHERE Result IS NULL OR DATALENGTH(Result) <> DATALENGTH(RTRIM(Result))
                 OR Result COLLATE Latin1_General_BIN2 NOT IN ('Success','Failure','Error','Skipped'))
      RAISERROR('Reported results contain an invalid outcome.',16,10);
  END TRY
  BEGIN CATCH
    INSERT tSQLt.TestResult(Class,TestCase,Result,Msg,TestEndTime)
      VALUES(@Class,@TestCase,'Error',ERROR_MESSAGE(),SYSDATETIME());
    RETURN;
  END CATCH;
  INSERT tSQLt.TestResult(Class,TestCase,CaseId,CaseDisplayName,Result,Msg,CaseState,CaseExecutionMode)
    SELECT @Class,@TestCase,P.CaseId,P.DisplayName,ISNULL(R.Result,'Error'),
           CASE WHEN R.CaseId IS NULL THEN 'Case was not reported.' ELSE R.Msg END,
           CASE WHEN R.CaseId IS NULL THEN 'NotRun' ELSE 'Reported' END,'Reported'
      FROM #tSQLt_CaseList P LEFT JOIN #tSQLt_CaseResults R
        ON DATALENGTH(R.CaseId) = DATALENGTH(P.CaseId)
       AND CONVERT(VARBINARY(MAX),R.CaseId) = CONVERT(VARBINARY(MAX),P.CaseId);
END;
GO
-- JUnit-style output with explicit identity and lifecycle metadata for case-aware runs.
CREATE PROCEDURE tSQLt.CaseXmlResultFormatter
AS
BEGIN
  DECLARE @Output XML;
  SELECT @Output = (
    SELECT C.Class AS [@name],
           COUNT(*) AS [@tests],
           SUM(CASE WHEN C.Result = 'Failure' THEN 1 ELSE 0 END) AS [@failures],
           SUM(CASE WHEN C.Result NOT IN ('Success','Failure','Skipped') OR C.Result IS NULL THEN 1 ELSE 0 END) AS [@errors],
           SUM(CASE WHEN C.Result = 'Skipped' THEN 1 ELSE 0 END) AS [@skipped],
           (SELECT R.Class AS [@classname],
                   CASE WHEN R.CaseId IS NULL THEN R.TestCase
                        ELSE R.TestCase + N' [' + R.CaseId + N'] ' + R.CaseDisplayName END AS [@name],
                   R.Name AS [@testname], R.CaseId AS [@caseid], R.CaseDisplayName AS [@displayname],
                   R.CaseExecutionMode AS [@executionmode],
                   R.CaseState AS [@state],
                   CAST(DATEDIFF(MILLISECOND,R.TestStartTime,R.TestEndTime)/1000.0 AS NUMERIC(20,3)) AS [@time],
                   CASE WHEN R.Result = 'Failure' THEN ISNULL(R.Msg,'') END AS [failure/@message],
                   CASE WHEN R.Result NOT IN ('Success','Failure','Skipped') OR R.Result IS NULL THEN ISNULL(R.Msg,'Unknown result.') END AS [error/@message],
                   CASE WHEN R.Result = 'Skipped' THEN ISNULL(R.Msg,'') END AS [skipped/@message]
              FROM tSQLt.TestResult R WHERE R.Class = C.Class ORDER BY R.Id
               FOR XML PATH('testcase'),TYPE)
      FROM tSQLt.TestResult C GROUP BY C.Class ORDER BY C.Class
       FOR XML PATH('testsuite'),ROOT('testsuites'),TYPE
  );
  EXEC tSQLt.Private_PrintXML @Output;
END;
GO
