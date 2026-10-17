EXEC tSQLt.NewTestClass N'AssertProcedureCalledTests';
GO
CREATE PROCEDURE AssertProcedureCalledTests.SetUp
AS
BEGIN
  EXEC(N'CREATE PROCEDURE AssertProcedureCalledTests.Target AS RETURN;');
  EXEC tSQLt.SpyProcedure N'AssertProcedureCalledTests.Target';
END;
GO
CREATE PROCEDURE AssertProcedureCalledTests.[test Called accepts one or multiple calls when count is omitted]
AS
BEGIN
  EXEC AssertProcedureCalledTests.Target;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target';
  EXEC AssertProcedureCalledTests.Target;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target', @ExpectedCallCount = NULL;
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test Called fails on zero calls when count is omitted]
AS
BEGIN
  EXEC tSQLt_testutil.AssertFailMessageEquals
      N'EXEC tSQLt.AssertProcedureCalled N''AssertProcedureCalledTests.Target'';',
      N'Expected [AssertProcedureCalledTests].[Target] to be called at least once, but was called 0 time(s).';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test Called accepts exact zero one and multiple calls]
AS
BEGIN
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target', 0;
  EXEC AssertProcedureCalledTests.Target;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target', 1;
  EXEC AssertProcedureCalledTests.Target;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target', 2;
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test Called reports too few calls]
AS
BEGIN
  EXEC AssertProcedureCalledTests.Target;
  EXEC tSQLt_testutil.AssertFailMessageEquals
      N'EXEC tSQLt.AssertProcedureCalled N''AssertProcedureCalledTests.Target'', 2;',
      N'Expected [AssertProcedureCalledTests].[Target] to be called 2 time(s), but was called 1 time(s).';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test Called reports too many calls]
AS
BEGIN
  EXEC AssertProcedureCalledTests.Target;
  EXEC AssertProcedureCalledTests.Target;
  EXEC tSQLt_testutil.AssertFailMessageEquals
      N'EXEC tSQLt.AssertProcedureCalled N''AssertProcedureCalledTests.Target'', 1;',
      N'Expected [AssertProcedureCalledTests].[Target] to be called 1 time(s), but was called 2 time(s).';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test Called supports BIGINT expectations]
AS
BEGIN
  EXEC tSQLt_testutil.AssertFailMessageEquals
      N'EXEC tSQLt.AssertProcedureCalled N''AssertProcedureCalledTests.Target'', 9223372036854775807;',
      N'Expected [AssertProcedureCalledTests].[Target] to be called 9223372036854775807 time(s), but was called 0 time(s).';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test Called prepends custom message]
AS
BEGIN
  EXEC tSQLt_testutil.AssertFailMessageEquals
      N'EXEC tSQLt.AssertProcedureCalled N''AssertProcedureCalledTests.Target'', @Message=N''Context: '';',
      N'Context: Expected [AssertProcedureCalledTests].[Target] to be called at least once, but was called 0 time(s).';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test NotCalled accepts zero calls]
AS
BEGIN
  EXEC tSQLt.AssertProcedureNotCalled N'AssertProcedureCalledTests.Target';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test NotCalled reports one call]
AS
BEGIN
  EXEC AssertProcedureCalledTests.Target;
  EXEC tSQLt_testutil.AssertFailMessageEquals
      N'EXEC tSQLt.AssertProcedureNotCalled N''AssertProcedureCalledTests.Target'';',
      N'Expected [AssertProcedureCalledTests].[Target] to be called 0 time(s), but was called 1 time(s).';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test NotCalled prepends custom message for multiple calls]
AS
BEGIN
  EXEC AssertProcedureCalledTests.Target;
  EXEC AssertProcedureCalledTests.Target;
  EXEC tSQLt_testutil.AssertFailMessageEquals
      N'EXEC tSQLt.AssertProcedureNotCalled N''AssertProcedureCalledTests.Target'', N''Context: '';',
      N'Context: Expected [AssertProcedureCalledTests].[Target] to be called 0 time(s), but was called 2 time(s).';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects negative counts even after a call]
AS
BEGIN
  EXEC AssertProcedureCalledTests.Target;
  EXEC tSQLt.ExpectException @ExpectedMessage = N'@ExpectedCallCount must be NULL or non-negative.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target', -1;
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects missing procedures]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Cannot assert calls to AssertProcedureCalledTests.Missing because the procedure does not exist.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Missing';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects NULL procedure names]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Cannot assert calls to NULL because the procedure does not exist.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureCalled NULL;
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects table targets]
AS
BEGIN
  CREATE TABLE AssertProcedureCalledTests.NotAProcedure (i INT);
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Cannot assert calls to AssertProcedureCalledTests.NotAProcedure because the procedure does not exist.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.NotAProcedure';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test NotCalled rejects procedures without a spy]
AS
BEGIN
  EXEC(N'CREATE PROCEDURE AssertProcedureCalledTests.Unspied AS RETURN;');
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Cannot assert calls to [AssertProcedureCalledTests].[Unspied] because SpyProcedure has not been applied.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureNotCalled N'AssertProcedureCalledTests.Unspied';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects a missing procedure marker]
AS
BEGIN
  EXEC sys.sp_dropextendedproperty @name=N'tSQLt.IsTempObject', @level0type=N'SCHEMA', @level0name=N'AssertProcedureCalledTests', @level1type=N'PROCEDURE', @level1name=N'Target';
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Cannot assert calls to [AssertProcedureCalledTests].[Target] because SpyProcedure has not been applied.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects a missing original procedure marker]
AS
BEGIN
  EXEC sys.sp_dropextendedproperty @name=N'tSQLt.Private_TestDouble_OrgObjectName', @level0type=N'SCHEMA', @level0name=N'AssertProcedureCalledTests', @level1type=N'PROCEDURE', @level1name=N'Target';
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Cannot assert calls to [AssertProcedureCalledTests].[Target] because SpyProcedure has not been applied.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects missing log tables]
AS
BEGIN
  DROP TABLE AssertProcedureCalledTests.Target_SpyProcedureLog;
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Cannot assert calls to [AssertProcedureCalledTests].[Target] because its SpyProcedure log table is missing or invalid.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureNotCalled N'AssertProcedureCalledTests.Target';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects ordinary replacement log tables]
AS
BEGIN
  DROP TABLE AssertProcedureCalledTests.Target_SpyProcedureLog;
  CREATE TABLE AssertProcedureCalledTests.Target_SpyProcedureLog (_id_ INT);
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Cannot assert calls to [AssertProcedureCalledTests].[Target] because its SpyProcedure log table is missing or invalid.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects views replacing log tables]
AS
BEGIN
  DROP TABLE AssertProcedureCalledTests.Target_SpyProcedureLog;
  EXEC(N'CREATE VIEW AssertProcedureCalledTests.Target_SpyProcedureLog AS SELECT 1 AS _id_;');
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Cannot assert calls to [AssertProcedureCalledTests].[Target] because its SpyProcedure log table is missing or invalid.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects invalid log markers]
AS
BEGIN
  EXEC sys.sp_updateextendedproperty @name=N'tSQLt.IsTempObject', @value=0, @level0type=N'SCHEMA', @level0name=N'AssertProcedureCalledTests', @level1type=N'TABLE', @level1name=N'Target_SpyProcedureLog';
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Cannot assert calls to [AssertProcedureCalledTests].[Target] because its SpyProcedure log table is missing or invalid.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects other databases]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Procedure call assertions require a procedure in the current database.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureCalled N'master.dbo.Target';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test rejects server qualified names]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessage = N'Procedure call assertions require a procedure in the current database.', @ExpectedSeverity = 16;
  EXEC tSQLt.AssertProcedureNotCalled N'Server.Database.dbo.Target';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test accepts current database qualification]
AS
BEGIN
  EXEC AssertProcedureCalledTests.Target;
  DECLARE @Name NVARCHAR(MAX);
  SET @Name = QUOTENAME(DB_NAME()) + N'.[AssertProcedureCalledTests].[Target]';
  EXEC tSQLt.AssertProcedureCalled @Name, 1;
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test handles quoted names with punctuation and unicode]
AS
BEGIN
  EXEC(N'CREATE SCHEMA [Odd ''.]] 名];');
  EXEC(N'CREATE PROCEDURE [Odd ''.]] 名].[Target ''.]] 名] AS RETURN;');
  EXEC tSQLt.SpyProcedure N'[Odd ''.]] 名].[Target ''.]] 名]';
  EXEC [Odd '.]] 名].[Target '.]] 名];
  EXEC tSQLt.AssertProcedureCalled N'[Odd ''.]] 名].[Target ''.]] 名]', 1;
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test handles schema omission]
AS
BEGIN
  EXEC(N'CREATE PROCEDURE dbo.AssertProcedureCalledTestsTarget AS RETURN;');
  EXEC tSQLt.SpyProcedure N'dbo.AssertProcedureCalledTestsTarget';
  EXEC dbo.AssertProcedureCalledTestsTarget;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTestsTarget', 1;
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test counts remaining rows rather than identity values]
AS
BEGIN
  EXEC AssertProcedureCalledTests.Target;
  EXEC AssertProcedureCalledTests.Target;
  DELETE AssertProcedureCalledTests.Target_SpyProcedureLog WHERE _id_ = 1;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target', 1;
  DELETE AssertProcedureCalledTests.Target_SpyProcedureLog;
  EXEC tSQLt.AssertProcedureNotCalled N'AssertProcedureCalledTests.Target';
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test uses the latest log after spying again]
AS
BEGIN
  EXEC AssertProcedureCalledTests.Target;
  EXEC tSQLt.SpyProcedure N'AssertProcedureCalledTests.Target';
  EXEC tSQLt.AssertProcedureNotCalled N'AssertProcedureCalledTests.Target';
  EXEC AssertProcedureCalledTests.Target;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.Target', 1;
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test counts calls with original behavior and custom commands]
AS
BEGIN
  CREATE TABLE #Effects (Value INT);
  EXEC(N'CREATE PROCEDURE AssertProcedureCalledTests.WithBehavior AS INSERT INTO #Effects VALUES (1);');
  EXEC tSQLt.SpyProcedure N'AssertProcedureCalledTests.WithBehavior', @CommandToExecute=N'INSERT INTO #Effects VALUES (2);', @CallOriginal=1;
  EXEC AssertProcedureCalledTests.WithBehavior;
  EXEC tSQLt.AssertProcedureCalled N'AssertProcedureCalledTests.WithBehavior', 1;
  DECLARE @Effects INT;
  SELECT @Effects = COUNT(*) FROM #Effects;
  EXEC tSQLt.AssertEquals 2, @Effects;
END;
GO

CREATE PROCEDURE AssertProcedureCalledTests.[test returns BIGINT count from private helper]
AS
BEGIN
  EXEC AssertProcedureCalledTests.Target;
  DECLARE @Count BIGINT, @Name NVARCHAR(MAX), @Result INT;
  EXEC @Result = tSQLt.Private_GetSpyProcedureCallCount N'AssertProcedureCalledTests.Target', @Count OUTPUT, @Name OUTPUT;
  EXEC tSQLt.AssertEquals 0, @Result;
  EXEC tSQLt.AssertEquals 1, @Count;
  EXEC tSQLt.AssertEqualsString N'[AssertProcedureCalledTests].[Target]', @Name;
END;
GO
