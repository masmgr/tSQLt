IF OBJECT_ID('tSQLt.AssertProcedureNotCalled') IS NOT NULL DROP PROCEDURE tSQLt.AssertProcedureNotCalled;
GO
---Build+
CREATE PROCEDURE tSQLt.AssertProcedureNotCalled
    @ProcedureName NVARCHAR(MAX),
    @Message NVARCHAR(MAX) = N''
AS
BEGIN
    DECLARE @ReturnCode INT;
    EXEC @ReturnCode = tSQLt.AssertProcedureCalled
        @ProcedureName = @ProcedureName,
        @ExpectedCallCount = 0,
        @Message = @Message;
    RETURN @ReturnCode;
END;
---Build-
GO
