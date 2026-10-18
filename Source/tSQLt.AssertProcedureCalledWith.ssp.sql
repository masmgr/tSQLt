IF OBJECT_ID('tSQLt.AssertProcedureCalledWith') IS NOT NULL DROP PROCEDURE tSQLt.AssertProcedureCalledWith;
GO
---Build+
CREATE PROCEDURE tSQLt.AssertProcedureCalledWith
    @ProcedureName NVARCHAR(MAX),
    @Expected NVARCHAR(MAX),
    @Message NVARCHAR(MAX) = NULL
AS
BEGIN
    EXEC tSQLt.Private_AssertProcedureCalls @ProcedureName, @Expected, 1, @Message, @CalledWith = 1;
END;
---Build-
GO
