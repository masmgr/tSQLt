IF OBJECT_ID('tSQLt.AssertProcedureCalls') IS NOT NULL DROP PROCEDURE tSQLt.AssertProcedureCalls;
GO
---Build+
CREATE PROCEDURE tSQLt.AssertProcedureCalls
    @ProcedureName NVARCHAR(MAX),
    @Expected NVARCHAR(MAX),
    @IgnoreOrder BIT = 1,
    @Message NVARCHAR(MAX) = NULL
AS
BEGIN
    EXEC tSQLt.Private_AssertProcedureCalls @ProcedureName, @Expected, @IgnoreOrder, @Message;
END;
---Build-
GO
