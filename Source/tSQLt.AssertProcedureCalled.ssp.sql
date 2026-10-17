IF OBJECT_ID('tSQLt.AssertProcedureCalled') IS NOT NULL DROP PROCEDURE tSQLt.AssertProcedureCalled;
GO
---Build+
CREATE PROCEDURE tSQLt.AssertProcedureCalled
    @ProcedureName NVARCHAR(MAX),
    @ExpectedCallCount BIGINT = NULL,
    @Message NVARCHAR(MAX) = N''
AS
BEGIN
    IF @ExpectedCallCount < 0
    BEGIN
        RAISERROR('@ExpectedCallCount must be NULL or non-negative.', 16, 10);
        RETURN 1;
    END;

    DECLARE @CallCount BIGINT, @QuotedProcedureName NVARCHAR(MAX), @ReturnCode INT;
    EXEC @ReturnCode = tSQLt.Private_GetSpyProcedureCallCount
        @ProcedureName = @ProcedureName,
        @CallCount = @CallCount OUTPUT,
        @QuotedProcedureName = @QuotedProcedureName OUTPUT;
    IF @ReturnCode <> 0 RETURN @ReturnCode;

    IF (@ExpectedCallCount IS NULL AND @CallCount = 0)
       OR @ExpectedCallCount <> @CallCount
    BEGIN
        DECLARE @FailureMessage NVARCHAR(MAX);
        SET @FailureMessage = N'Expected ' + @QuotedProcedureName + N' to be called '
            + CASE WHEN @ExpectedCallCount IS NULL THEN N'at least once'
                   ELSE CAST(@ExpectedCallCount AS NVARCHAR(20)) + N' time(s)' END
            + N', but was called ' + CAST(@CallCount AS NVARCHAR(20)) + N' time(s).';
        EXEC tSQLt.Fail @Message, @FailureMessage;
        RETURN 1;
    END;
    RETURN 0;
END;
---Build-
GO
