IF OBJECT_ID('tSQLt.Private_GetSpyProcedureCallCount') IS NOT NULL DROP PROCEDURE tSQLt.Private_GetSpyProcedureCallCount;
GO
---Build+
CREATE PROCEDURE tSQLt.Private_GetSpyProcedureCallCount
    @ProcedureName NVARCHAR(MAX),
    @CallCount BIGINT OUTPUT,
    @QuotedProcedureName NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SELECT @CallCount = NULL, @QuotedProcedureName = NULL;

    IF PARSENAME(@ProcedureName, 4) IS NOT NULL
       OR (PARSENAME(@ProcedureName, 3) IS NOT NULL AND PARSENAME(@ProcedureName, 3) <> DB_NAME())
    BEGIN
        RAISERROR('Procedure call assertions require a procedure in the current database.', 16, 10);
        RETURN 1;
    END;

    DECLARE @ProcedureObjectId INT;
    SET @ProcedureObjectId = OBJECT_ID(@ProcedureName);
    IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE object_id = @ProcedureObjectId)
    BEGIN
        DECLARE @DisplayName NVARCHAR(MAX);
        SET @DisplayName = COALESCE(@ProcedureName, N'NULL');
        RAISERROR('Cannot assert calls to %s because the procedure does not exist.', 16, 10, @DisplayName);
        RETURN 1;
    END;

    SET @QuotedProcedureName = QUOTENAME(OBJECT_SCHEMA_NAME(@ProcedureObjectId)) + N'.' + QUOTENAME(OBJECT_NAME(@ProcedureObjectId));
    IF NOT EXISTS (SELECT 1 FROM sys.extended_properties
                   WHERE class = 1 AND major_id = @ProcedureObjectId AND minor_id = 0
                     AND name = N'tSQLt.IsTempObject' AND CAST(value AS NVARCHAR(4000)) = N'1')
       OR NOT EXISTS (SELECT 1 FROM sys.extended_properties
                       WHERE class = 1 AND major_id = @ProcedureObjectId AND minor_id = 0
                         AND name = N'tSQLt.Private_TestDouble_OrgObjectName')
    BEGIN
        RAISERROR('Cannot assert calls to %s because SpyProcedure has not been applied.', 16, 10, @QuotedProcedureName);
        RETURN 1;
    END;

    DECLARE @LogTableName NVARCHAR(MAX), @LogTableObjectId INT;
    SET @LogTableName = QUOTENAME(OBJECT_SCHEMA_NAME(@ProcedureObjectId)) + N'.' + QUOTENAME(OBJECT_NAME(@ProcedureObjectId) + N'_SpyProcedureLog');
    SET @LogTableObjectId = OBJECT_ID(@LogTableName, N'U');
    IF @LogTableObjectId IS NULL
       OR NOT EXISTS (SELECT 1 FROM sys.extended_properties
                       WHERE class = 1 AND major_id = @LogTableObjectId AND minor_id = 0
                         AND name = N'tSQLt.IsTempObject' AND CAST(value AS NVARCHAR(4000)) = N'1')
    BEGIN
        RAISERROR('Cannot assert calls to %s because its SpyProcedure log table is missing or invalid.', 16, 10, @QuotedProcedureName);
        RETURN 1;
    END;

    DECLARE @Command NVARCHAR(MAX);
    SET @Command = N'SELECT @CallCount = COUNT_BIG(*) FROM ' + @LogTableName + N';';
    EXEC sys.sp_executesql @Command, N'@CallCount BIGINT OUTPUT', @CallCount OUTPUT;
    RETURN 0;
END;
---Build-
GO
