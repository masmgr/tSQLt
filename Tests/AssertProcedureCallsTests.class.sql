EXEC tSQLt.NewTestClass 'AssertProcedureCallsTests';
GO
CREATE PROCEDURE AssertProcedureCallsTests.SetUp
AS
BEGIN
  EXEC('CREATE PROCEDURE AssertProcedureCallsTests.Target @A INT, @B NVARCHAR(MAX) = NULL AS RETURN;');
  EXEC tSQLt.SpyProcedure 'AssertProcedureCallsTests.Target';
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
  EXEC tSQLt.ExpectException @ExpectedMessagePattern = '%must have a SpyProcedure log%';
  EXEC tSQLt.AssertProcedureCalls 'AssertProcedureCallsTests.Unspied', '#Expected';
END;
GO
