EXEC tSQLt.NewTestClass 'AssertProcedureCallsTests';
GO
CREATE PROCEDURE AssertProcedureCallsTests.SetUp
AS
BEGIN
  EXEC('CREATE PROCEDURE AssertProcedureCallsTests.Target @A INT, @B NVARCHAR(MAX) = NULL AS RETURN;');
  EXEC tSQLt.SpyProcedure 'AssertProcedureCallsTests.Target';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test ordered calls use renamed log identity instead of argument values]
AS
BEGIN
  EXEC('CREATE PROCEDURE AssertProcedureCallsTests.Collision @_id_ INT, @_id__ INT, @A INT AS RETURN;');
  EXEC tSQLt.SpyProcedure 'AssertProcedureCallsTests.Collision';
  EXEC AssertProcedureCallsTests.Collision 20, 30, 100;
  EXEC AssertProcedureCallsTests.Collision 10, 40, 200;
  CREATE TABLE #Expected(_id_ INT, _id__ INT, A INT);
  INSERT #Expected VALUES(1,30,100),(2,40,200);
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Collision', '#Expected', @IgnoreOrder=0;
  EXEC tSQLt.AssertProcedureCalled 'AssertProcedureCallsTests.Collision', 2;
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test renamed log identity is not an argument column]
AS
BEGIN
  EXEC('CREATE PROCEDURE AssertProcedureCallsTests.Collision @_id_ INT AS RETURN;');
  EXEC tSQLt.SpyProcedure 'AssertProcedureCallsTests.Collision';
  CREATE TABLE #Expected(_id__ INT);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%unknown argument column%';
  EXEC tSQLt.AssertProcedureCalledWith 'AssertProcedureCallsTests.Collision', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test ordinary log table does not make an unspied procedure valid]
AS
BEGIN
  EXEC('CREATE PROCEDURE AssertProcedureCallsTests.Unspied AS RETURN;');
  CREATE TABLE AssertProcedureCallsTests.Unspied_SpyProcedureLog(_id_ INT, A INT);
  CREATE TABLE #Expected(A INT);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%SpyProcedure has not been applied%';
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Unspied', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test CalledWith rejects an invalid log marker]
AS
BEGIN
  EXEC sys.sp_updateextendedproperty @name=N'tSQLt.IsTempObject', @value=0,
    @level0type=N'SCHEMA', @level0name=N'AssertProcedureCallsTests',
    @level1type=N'TABLE', @level1name=N'Target_SpyProcedureLog';
  CREATE TABLE #Expected(A INT);
  INSERT #Expected VALUES(1);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%log table is missing or invalid%';
  EXEC tSQLt.AssertProcedureCalledWith 'AssertProcedureCallsTests.Target', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test procedures in other databases are rejected]
AS
BEGIN
  CREATE TABLE #Expected(A INT);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%procedure in the current database%';
  EXEC tSQLt.AssertProcedureCalls 'master.dbo.Target', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test expected tables in other databases are rejected]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%expected table must be in the current database%';
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', 'master.dbo.Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test omitted arguments and default order are ignored]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1, 'ignored';
  EXEC AssertProcedureCallsTests.Target 2, 'different';
  CREATE TABLE #Expected(A INT);
  INSERT #Expected VALUES(2),(1);
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test explicit NULL matches NULL]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1, NULL;
  CREATE TABLE #Expected(B NVARCHAR(MAX));
  INSERT #Expected VALUES(NULL);
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test NULL does not match a value]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1, 'value';
  CREATE TABLE #Expected(B NVARCHAR(MAX));
  INSERT #Expected VALUES(NULL);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertProcedureCalls ''AssertProcedureCallsTests.Target'', ''#Expected'';',
    '%Procedure calls differ%';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test equal duplicate multiplicities pass]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1;
  EXEC AssertProcedureCallsTests.Target 1;
  CREATE TABLE #Expected(A INT);
  INSERT #Expected VALUES(1),(1);
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test extra duplicate fails]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1;
  EXEC AssertProcedureCallsTests.Target 1;
  CREATE TABLE #Expected(A INT);
  INSERT #Expected VALUES(1);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertProcedureCalls ''AssertProcedureCallsTests.Target'', ''#Expected'';',
    '%Procedure calls differ%';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test missing duplicate fails]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1;
  CREATE TABLE #Expected(A INT);
  INSERT #Expected VALUES(1),(1);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertProcedureCalls ''AssertProcedureCallsTests.Target'', ''#Expected'';',
    '%Procedure calls differ%';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test ordered calls use relative order instead of identity values]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1;
  EXEC AssertProcedureCallsTests.Target 2;
  CREATE TABLE #Expected(_id_ INT, A INT);
  INSERT #Expected VALUES(20,2),(10,1);
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '#Expected', @IgnoreOrder=0;
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test reversed order fails when requested]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1;
  EXEC AssertProcedureCallsTests.Target 2;
  CREATE TABLE #Expected(_id_ INT, A INT);
  INSERT #Expected VALUES(1,2),(2,1);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertProcedureCalls ''AssertProcedureCallsTests.Target'', ''#Expected'', @IgnoreOrder=0;',
    '%Procedure calls differ%';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test order metadata is ignored by default]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1;
  CREATE TABLE #Expected(_id_ INT, A INT);
  INSERT #Expected VALUES(99,1);
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test ordered comparison rejects duplicate ordinals]
AS
BEGIN
  CREATE TABLE #Expected(_id_ INT, A INT);
  INSERT #Expected VALUES(1,1),(1,2);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%unique, non-NULL _id_%';
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '#Expected', @IgnoreOrder=0;
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test ordered comparison requires metadata]
AS
BEGIN
  CREATE TABLE #Expected(A INT);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%ordered expectations require%';
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '#Expected', @IgnoreOrder=0;
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test unknown arguments are rejected]
AS
BEGIN
  CREATE TABLE #Expected(UnknownArgument INT);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%unknown argument column%';
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test empty expectations assert no calls]
AS
BEGIN
  CREATE TABLE #Expected(A INT);
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test no argument projection still checks multiplicity]
AS
BEGIN
  EXEC('CREATE PROCEDURE AssertProcedureCallsTests.NoArgs AS RETURN;');
  EXEC tSQLt.SpyProcedure 'AssertProcedureCallsTests.NoArgs';
  EXEC AssertProcedureCallsTests.NoArgs;
  EXEC AssertProcedureCallsTests.NoArgs;
  CREATE TABLE #Expected(_id_ INT);
  INSERT #Expected VALUES(1),(2);
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.NoArgs', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test schema tables and quoted argument columns work]
AS
BEGIN
  EXEC('CREATE PROCEDURE AssertProcedureCallsTests.Quoted @select INT AS RETURN;');
  EXEC tSQLt.SpyProcedure 'AssertProcedureCallsTests.Quoted';
  EXEC AssertProcedureCallsTests.Quoted 42;
  CREATE TABLE AssertProcedureCallsTests.[Expected calls]([select] INT);
  INSERT AssertProcedureCallsTests.[Expected calls] VALUES(42);
  EXEC tSQLt.AssertProcedureCalls '[AssertProcedureCallsTests].[Quoted]', '[AssertProcedureCallsTests].[Expected calls]';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test CalledWith accepts any matching call and ignores other calls]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1, 'other';
  EXEC AssertProcedureCallsTests.Target 2, NULL;
  EXEC AssertProcedureCallsTests.Target 2, NULL;
  CREATE TABLE #Expected(A INT, B NVARCHAR(MAX));
  INSERT #Expected VALUES(2,NULL);
  EXEC tSQLt.AssertProcedureCalledWith 'AssertProcedureCallsTests.Target', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test CalledWith rejects mismatched arguments]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1, 'other';
  CREATE TABLE #Expected(A INT);
  INSERT #Expected VALUES(2);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertProcedureCalledWith ''AssertProcedureCallsTests.Target'', ''#Expected'';',
    '%Procedure calls differ%';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test CalledWith requires one expected row]
AS
BEGIN
  CREATE TABLE #Expected(A INT);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%exactly one row%';
  EXEC tSQLt.AssertProcedureCalledWith 'AssertProcedureCallsTests.Target', '#Expected';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test failure includes missing and extra argument values and user message]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 123;
  CREATE TABLE #Expected(A INT);
  INSERT #Expected VALUES(456);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertProcedureCalls ''AssertProcedureCallsTests.Target'', ''#Expected'', @Message=''custom context'';',
    '%custom context%Procedure calls differ%<%456%>%123%';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test quoted local temporary expectations work]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1;
  CREATE TABLE [#Expected calls](A INT);
  INSERT [#Expected calls] VALUES(1);
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '[#Expected calls]';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test no selected arguments still rejects extra calls]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1;
  EXEC AssertProcedureCallsTests.Target 2;
  CREATE TABLE #Expected(_id_ INT);
  INSERT #Expected VALUES(1);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertProcedureCalls ''AssertProcedureCallsTests.Target'', ''#Expected'';',
    '%Procedure calls differ%';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test CalledWith fails without calls]
AS
BEGIN
  CREATE TABLE #Expected(A INT);
  INSERT #Expected VALUES(1);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertProcedureCalledWith ''AssertProcedureCallsTests.Target'', ''#Expected'';',
    '%Procedure calls differ%';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test CalledWith rejects a nonmatching second argument]
AS
BEGIN
  EXEC AssertProcedureCallsTests.Target 1, 'actual';
  CREATE TABLE #Expected(A INT, B NVARCHAR(MAX));
  INSERT #Expected VALUES(1,'expected');
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertProcedureCalledWith ''AssertProcedureCallsTests.Target'', ''#Expected'';',
    '%Procedure calls differ%';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test ordered comparison rejects NULL ordinals]
AS
BEGIN
  CREATE TABLE #Expected(_id_ INT, A INT);
  INSERT #Expected VALUES(NULL,1);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%unique, non-NULL _id_%';
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '#Expected', @IgnoreOrder=0;
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test missing expected table is rejected]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%expected table does not exist%';
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Target', '#Missing';
END;
GO
CREATE PROCEDURE AssertProcedureCallsTests.[test procedure without spy log is rejected]
AS
BEGIN
  EXEC('CREATE PROCEDURE AssertProcedureCallsTests.Unspied AS RETURN;');
  CREATE TABLE #Expected(A INT);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%SpyProcedure has not been applied%';
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Unspied', '#Expected';
END;
GO
