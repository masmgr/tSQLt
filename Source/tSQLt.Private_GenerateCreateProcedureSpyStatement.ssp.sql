IF OBJECT_ID('tSQLt.Private_GenerateCreateProcedureSpyStatement') IS NOT NULL DROP PROCEDURE tSQLt.Private_GenerateCreateProcedureSpyStatement;
GO
---Build+
CREATE PROCEDURE tSQLt.Private_GenerateCreateProcedureSpyStatement
    @ProcedureObjectId INT,
    @OriginalProcedureName NVARCHAR(MAX),
    @UnquotedNewNameOfProcedure NVARCHAR(MAX) = NULL,
    @LogTableName NVARCHAR(MAX),
    @CommandToExecute NVARCHAR(MAX),
    @CallOriginal BIT,
    @CreateProcedureStatement NVARCHAR(MAX) OUTPUT,
    @CreateLogTableStatement NVARCHAR(MAX) OUTPUT,
    @MaxCalls INT = NULL
AS
BEGIN
    DECLARE @ProcParmListForInsert NVARCHAR(MAX) = '';
    DECLARE @ProcParmListForCall NVARCHAR(MAX) = '';
    DECLARE @TableColList NVARCHAR(MAX) = '';
    DECLARE @ProcParmTypeList NVARCHAR(MAX) = '';
    DECLARE @TableColTypeList NVARCHAR(MAX) = '';

    DECLARE @ReturnValueVariableName sysname = '@SpyProcedureReturnValue';
    DECLARE @ReturnValueVariableSuffix INT = 0;
    WHILE EXISTS(SELECT 1 FROM sys.parameters WHERE object_id = @ProcedureObjectId AND name = @ReturnValueVariableName)
       OR CHARINDEX(@ReturnValueVariableName, ISNULL(@CommandToExecute, '')) > 0
    BEGIN
      SET @ReturnValueVariableSuffix = @ReturnValueVariableSuffix + 1;
      SET @ReturnValueVariableName = '@SpyProcedureReturnValue' + CAST(@ReturnValueVariableSuffix AS NVARCHAR(10));
    END;

    -- Input cursor parameters must be passed without OUTPUT, whereas a newly
    -- returned cursor needs OUTPUT. Use separate, initially unassigned variables
    -- for the latter so mixed input/output cursor calls remain valid.
    DECLARE @CursorVariablePrefix sysname = '@SpyProcedureCursor';
    DECLARE @CursorVariableSuffix INT = 0;
    WHILE EXISTS(SELECT 1 FROM sys.parameters WHERE object_id = @ProcedureObjectId AND LEFT(name,LEN(@CursorVariablePrefix)) = @CursorVariablePrefix)
       OR CHARINDEX(@CursorVariablePrefix, ISNULL(@CommandToExecute, '')) > 0
    BEGIN
      SET @CursorVariableSuffix = @CursorVariableSuffix + 1;
      SET @CursorVariablePrefix = '@SpyProcedureCursor' + CAST(@CursorVariableSuffix AS NVARCHAR(10)) + '_';
    END;
    DECLARE @CursorDeclarations NVARCHAR(MAX) = '';
    DECLARE @CursorParameterList NVARCHAR(MAX) = '';
    DECLARE @CursorArgumentList NVARCHAR(MAX) = '';
    DECLARE @CursorCallExpression NVARCHAR(MAX) = 'N''EXEC ' + @ReturnValueVariableName + ' = @SpyProcedureOriginalObjectName ''';
    DECLARE @CursorAssignments NVARCHAR(MAX) = '';
    DECLARE @OutputCursorVariable NVARCHAR(MAX);
    DECLARE @InputCursorVariable NVARCHAR(MAX);
    DECLARE @InputCursorStatusVariable NVARCHAR(MAX);
    DECLARE @CursorNumber INT = 0;

    DECLARE @SeparatorWithoutCursor CHAR(1) = '';
    DECLARE @SeparatorWithCursor CHAR(1) = '';
    DECLARE @ParamName sysname;
    DECLARE @TypeName NVARCHAR(MAX);
    DECLARE @IsOutput BIT;
    DECLARE @IsCursorRef BIT;
    DECLARE @IsTableType BIT;
            
    DECLARE Parameters CURSOR FOR
     SELECT p.name, t.TypeName, p.is_output, p.is_cursor_ref, t.IsTableType
       FROM sys.parameters p
       CROSS APPLY tSQLt.Private_GetFullTypeName(p.user_type_id,p.max_length,p.precision,p.scale,NULL) t
      WHERE object_id = @ProcedureObjectId;
    
    OPEN Parameters;
    
    FETCH NEXT FROM Parameters INTO @ParamName, @TypeName, @IsOutput, @IsCursorRef, @IsTableType;
    WHILE (@@FETCH_STATUS = 0)
    BEGIN
        IF @IsCursorRef = 0
        BEGIN
            SELECT @ProcParmListForInsert = @ProcParmListForInsert + @SeparatorWithoutCursor + 
                                   CASE WHEN @IsTableType = 1 
                                     THEN '(SELECT * FROM '+@ParamName+' FOR XML PATH(''row''),TYPE,ROOT('''+STUFF(@ParamName,1,1,'')+'''))' 
                                     ELSE @ParamName 
                                   END, 
                   @TableColList = @TableColList + @SeparatorWithoutCursor + '[' + STUFF(@ParamName,1,1,'') + ']', 
                   @ProcParmTypeList = @ProcParmTypeList + @SeparatorWithCursor + @ParamName + ' ' + @TypeName + 
                                       CASE WHEN @IsTableType = 1 THEN ' READONLY' ELSE ' = NULL ' END+ 
                                       CASE WHEN @IsOutput = 1 THEN ' OUT' ELSE '' END, 
                   @TableColTypeList = @TableColTypeList + ',[' + STUFF(@ParamName,1,1,'') + '] ' + 
                          CASE 
                               WHEN @IsTableType = 1
                               THEN 'XML'
                               WHEN @TypeName LIKE '%nchar%'
                                 OR @TypeName LIKE '%nvarchar%'
                               THEN 'NVARCHAR(MAX)'
                               WHEN @TypeName LIKE '%char%'
                               THEN 'VARCHAR(MAX)'
                               ELSE @TypeName
                          END + ' NULL';

            SELECT @SeparatorWithoutCursor = ',';        

            SET @CursorParameterList = @CursorParameterList + ',' + @ParamName + ' ' + @TypeName +
                                       CASE WHEN @IsTableType = 1 THEN ' READONLY' ELSE '' END +
                                       CASE WHEN @IsOutput = 1 THEN ' OUTPUT' ELSE '' END;
            SET @CursorArgumentList = @CursorArgumentList + ',' + @ParamName + CASE WHEN @IsOutput = 1 THEN ' OUTPUT' ELSE '' END;
            SET @CursorCallExpression = @CursorCallExpression + '+N''' + @SeparatorWithCursor + @ParamName + CASE WHEN @IsOutput = 1 THEN ' OUTPUT' ELSE '' END + '''';
        END
        ELSE
        BEGIN
            SELECT @ProcParmTypeList = @ProcParmTypeList + @SeparatorWithCursor + @ParamName + ' CURSOR VARYING OUTPUT';

            SET @CursorNumber = @CursorNumber + 1;
            SET @OutputCursorVariable = @CursorVariablePrefix + 'Output' + CAST(@CursorNumber AS NVARCHAR(10));
            SET @InputCursorVariable = @CursorVariablePrefix + 'Input' + CAST(@CursorNumber AS NVARCHAR(10));
            SET @InputCursorStatusVariable = @InputCursorVariable + 'Status';
            SET @CursorDeclarations = @CursorDeclarations + 'DECLARE ' + @OutputCursorVariable + ' CURSOR;' +
              'DECLARE ' + @InputCursorVariable + ' CURSOR;SET ' + @InputCursorVariable + ' = ' + @ParamName + ';' +
              'DECLARE ' + @InputCursorStatusVariable + ' INT = CURSOR_STATUS(''variable'',''' + @InputCursorVariable + ''');';
            SET @CursorParameterList = @CursorParameterList + ',' + @ParamName + ' CURSOR OUTPUT,' + @OutputCursorVariable + ' CURSOR OUTPUT';
            SET @CursorArgumentList = @CursorArgumentList + ',' + @InputCursorVariable + ',' + @OutputCursorVariable + ' OUTPUT';
            SET @CursorCallExpression = @CursorCallExpression + '+N''' + @SeparatorWithCursor + '''+CASE WHEN ' + @InputCursorStatusVariable + ' >= -1 THEN N''' + @ParamName + ''' ELSE N''' + @OutputCursorVariable + ' OUTPUT'' END';
            SET @CursorAssignments = @CursorAssignments + 'IF ' + @InputCursorStatusVariable + ' = -2 SET ' + @ParamName + ' = ' + @OutputCursorVariable + ';';
        END;
        SELECT 
            @ProcParmListForCall = @ProcParmListForCall + @SeparatorWithCursor + @ParamName + 
            CASE 
              WHEN @IsOutput = 1 AND @IsCursorRef <> 1
                THEN ' OUT' 
              ELSE '' 
            END;
        SELECT @SeparatorWithCursor = ',';

        FETCH NEXT FROM Parameters INTO @ParamName, @TypeName, @IsOutput, @IsCursorRef, @IsTableType;
    END;
    
    CLOSE Parameters;
    DEALLOCATE Parameters;
    
    DECLARE @InsertStmt NVARCHAR(MAX);
    SELECT @InsertStmt = 'INSERT INTO ' + @LogTableName + 
                         CASE WHEN @TableColList = '' THEN ' DEFAULT VALUES'
                              ELSE ' (' + @TableColList + ') SELECT ' + @ProcParmListForInsert
                         END + ';';
                         
    DECLARE @LogIdentityColumnName NVARCHAR(MAX) = '_id_';
    WHILE EXISTS(SELECT 1 FROM sys.parameters WHERE object_id = @ProcedureObjectId AND is_cursor_ref = 0 AND name = '@' + @LogIdentityColumnName)
    BEGIN
      SET @LogIdentityColumnName = @LogIdentityColumnName + '_';
    END;
    SELECT @CreateLogTableStatement = 'CREATE TABLE ' + @LogTableName + ' (' + QUOTENAME(@LogIdentityColumnName) + ' int IDENTITY(1,1) PRIMARY KEY CLUSTERED ' + @TableColTypeList + ');';

    DECLARE @OriginalProcedureCall NVARCHAR(MAX) = 'EXEC ' + @ReturnValueVariableName + ' = @SpyProcedureOriginalObjectName ' + @ProcParmListForCall + ';';
    IF @CursorDeclarations <> ''
    BEGIN
      SET @OriginalProcedureCall = @CursorDeclarations +
        'DECLARE ' + @CursorVariablePrefix + 'Command NVARCHAR(MAX);' +
        'SET ' + @CursorVariablePrefix + 'Command = ' + @CursorCallExpression + ';' +
        'EXEC sys.sp_executesql ' + @CursorVariablePrefix + 'Command,N''' +
          REPLACE('@SpyProcedureOriginalObjectName NVARCHAR(MAX),' + @ReturnValueVariableName + ' INT OUTPUT' + @CursorParameterList,'''','''''') +
          ''',@SpyProcedureOriginalObjectName,' + @ReturnValueVariableName + ' OUTPUT' + @CursorArgumentList + ';' + @CursorAssignments;
    END;

    SELECT @CreateProcedureStatement = 
             'CREATE PROCEDURE ' + @OriginalProcedureName + ' ' + @ProcParmTypeList + 
             ' AS BEGIN ' + 
                CASE WHEN @MaxCalls IS NULL THEN '' ELSE
                  'IF (SELECT COUNT_BIG(*) FROM ' + @LogTableName + ') >= ' + CONVERT(NVARCHAR(20),@MaxCalls) +
                  ' BEGIN RAISERROR(''SpyProcedure: maximum call count exceeded.'',16,10); RETURN; END;'
                END +
                ISNULL(@InsertStmt,'') + 
                ISNULL('DECLARE @SpyProcedureOriginalObjectName NVARCHAR(MAX) = '''+REPLACE(QUOTENAME(OBJECT_SCHEMA_NAME(@ProcedureObjectId))+'.'+QUOTENAME(@UnquotedNewNameOfProcedure),'''','''''')+''';','')+
                ISNULL(@CommandToExecute + ';', '') +
                CHAR(13)+CHAR(10)+/*CR,LF*/
                CASE WHEN @CallOriginal = 1 
                     THEN 'DECLARE ' + @ReturnValueVariableName + ' INT;' +
                          @OriginalProcedureCall +
                          'RETURN ' + @ReturnValueVariableName + ';'
                     ELSE 'RETURN;'
                END +
             ' END;';
    --RAISERROR(@CreateProcedureStatement, 0, 1) WITH NOWAIT;

    RETURN;
END;
---Build-
GO
