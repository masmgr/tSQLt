EXEC tSQLt.NewTestClass 'SpyProcedureTests';
GO
CREATE PROCEDURE SpyProcedureTests.[test MaxCalls preserves output cursor and original return status]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.Limited @C CURSOR VARYING OUTPUT AS
        BEGIN SET @C = CURSOR LOCAL STATIC FOR SELECT 42; OPEN @C; RETURN -37; END;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.Limited', @CallOriginal=1, @MaxCalls=1;
  DECLARE @C CURSOR;
  DECLARE @Status INT, @Value INT;
  EXEC @Status = SpyProcedureTests.Limited @C OUTPUT;
  FETCH NEXT FROM @C INTO @Value;
  CLOSE @C;
  DEALLOCATE @C;
  EXEC tSQLt.AssertEquals -37, @Status;
  EXEC tSQLt.AssertEquals 42, @Value;
  EXEC tSQLt.AssertProcedureCalled 'SpyProcedureTests.Limited', 1;
  EXEC tSQLt.ExpectException @ExpectedMessage='SpyProcedure: maximum call count exceeded.';
  EXEC SpyProcedureTests.Limited @C OUTPUT;
END;
GO
CREATE PROCEDURE SpyProcedureTests.[test MaxCalls rejects excess calls before logging command and original]
AS
BEGIN
  CREATE TABLE SpyProcedureTests.Effects(SourceName VARCHAR(10));
  EXEC('CREATE PROCEDURE SpyProcedureTests.Limited AS INSERT SpyProcedureTests.Effects VALUES(''original'');');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.Limited',
       @CommandToExecute='INSERT SpyProcedureTests.Effects VALUES(''command'')', @CallOriginal=1, @MaxCalls=1;
  EXEC SpyProcedureTests.Limited;
  DECLARE @Error NVARCHAR(MAX);
  BEGIN TRY
    EXEC SpyProcedureTests.Limited;
  END TRY
  BEGIN CATCH
    SET @Error = ERROR_MESSAGE();
  END CATCH;
  EXEC tSQLt.AssertEqualsString 'SpyProcedure: maximum call count exceeded.', @Error;
  DECLARE @LogCount INT = (SELECT COUNT(*) FROM SpyProcedureTests.Limited_SpyProcedureLog);
  DECLARE @EffectCount INT = (SELECT COUNT(*) FROM SpyProcedureTests.Effects);
  EXEC tSQLt.AssertEquals 1, @LogCount;
  EXEC tSQLt.AssertEquals 2, @EffectCount;
END;
GO
CREATE PROCEDURE SpyProcedureTests.[test MaxCalls zero rejects the first call]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.Limited AS RETURN;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.Limited', @MaxCalls=0;
  EXEC tSQLt.ExpectException @ExpectedMessage='SpyProcedure: maximum call count exceeded.';
  EXEC SpyProcedureTests.Limited;
END;
GO
CREATE PROCEDURE SpyProcedureTests.[test MaxCalls negative is rejected before replacing the procedure]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.Limited AS RETURN;');
  EXEC tSQLt.ExpectException @ExpectedMessage='SpyProcedure: @MaxCalls must be NULL or nonnegative.';
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.Limited', @MaxCalls=-1;
END;
GO
CREATE PROCEDURE SpyProcedureTests.[test MaxCalls stops recursive original calls]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.Limited AS EXEC SpyProcedureTests.Limited;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.Limited', @CallOriginal=1, @MaxCalls=3;
  DECLARE @Error NVARCHAR(MAX);
  BEGIN TRY
    EXEC SpyProcedureTests.Limited;
  END TRY
  BEGIN CATCH
    SET @Error = ERROR_MESSAGE();
  END CATCH;
  EXEC tSQLt.AssertEqualsString 'SpyProcedure: maximum call count exceeded.', @Error;
  DECLARE @LogCount INT = (SELECT COUNT(*) FROM SpyProcedureTests.Limited_SpyProcedureLog);
  EXEC tSQLt.AssertEquals 3, @LogCount;
END;
GO
CREATE PROC SpyProcedureTests.[test CallOriginal preserves a nonzero return status]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.ReturnStatus AS RETURN 37;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.ReturnStatus', @CallOriginal = 1;

  DECLARE @Actual INT;
  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.ReturnStatus';
  EXEC @Actual = @ProcedureName;

  EXEC tSQLt.AssertEquals @Expected = 37, @Actual = @Actual;
END;
GO
CREATE PROC SpyProcedureTests.[test CallOriginal preserves a negative return status]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.ReturnStatus AS RETURN -7;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.ReturnStatus', @CallOriginal = 1;

  DECLARE @Actual INT;
  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.ReturnStatus';
  EXEC @Actual = @ProcedureName;

  EXEC tSQLt.AssertEquals @Expected = -7, @Actual = @Actual;
END;
GO
CREATE PROC SpyProcedureTests.[test return status variable does not collide with procedure parameters]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.ReturnStatus @SpyProcedureReturnValue INT, @SpyProcedureReturnValue1 INT
        AS RETURN @SpyProcedureReturnValue + @SpyProcedureReturnValue1;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.ReturnStatus', @CallOriginal = 1;

  DECLARE @Actual INT;
  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.ReturnStatus';
  EXEC @Actual = @ProcedureName 12, 25;

  EXEC tSQLt.AssertEquals @Expected = 37, @Actual = @Actual;
END;
GO
CREATE PROC SpyProcedureTests.[test return status variable does not collide with custom command variables]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.ReturnStatus AS RETURN 37;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.ReturnStatus',
       @CommandToExecute = 'DECLARE @SpyProcedureReturnValue INT; DECLARE @SpyProcedureReturnValue1 INT;',
       @CallOriginal = 1;

  DECLARE @Actual INT;
  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.ReturnStatus';
  EXEC @Actual = @ProcedureName;

  EXEC tSQLt.AssertEquals @Expected = 37, @Actual = @Actual;
END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure should allow tester to not execute behavior of procedure]
AS
BEGIN

    EXEC('CREATE PROC dbo.InnerProcedure AS EXEC tSQLt.Fail ''Original InnerProcedure was executed'';');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure;

END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure should allow tester to not execute behavior of procedure with a parameter]
AS
BEGIN

    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(MAX) AS EXEC tSQLt.Fail ''InnerProcedure was executed '',@P1;');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure 'with a parameter';

END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure should allow tester to not execute behavior of procedure with multiple parameters]
AS
BEGIN

    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(MAX), @P2 VARCHAR(MAX), @P3 VARCHAR(MAX) ' +
         'AS EXEC tSQLt.Fail ''InnerProcedure was executed '',@P1,@P2,@P3;');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure 'with', 'multiple', 'parameters';

END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure should log calls]
AS
BEGIN

    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(MAX), @P2 VARCHAR(MAX), @P3 VARCHAR(MAX) ' +
         'AS EXEC tSQLt.Fail ''InnerProcedure was executed '',@P1,@P2,@P3;');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure 'with', 'multiple', 'parameters';

    IF NOT EXISTS(SELECT 1 FROM dbo.InnerProcedure_SpyProcedureLog)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged!';
    END;

END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure should log calls with varchar parameters]
AS
BEGIN

    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(MAX), @P2 VARCHAR(10), @P3 VARCHAR(8000) ' +
         'AS EXEC tSQLt.Fail ''InnerProcedure was executed '',@P1,@P2,@P3;');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure 'with', 'multiple', 'parameters';


    IF NOT EXISTS(SELECT 1
                   FROM dbo.InnerProcedure_SpyProcedureLog
                  WHERE P1 = 'with'
                    AND P2 = 'multiple'
                    AND P3 = 'parameters')
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END;

END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure logs a parameter named _id_ without an identity collision]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.IdParameter @_id_ INT AS RETURN;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.IdParameter';

  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.IdParameter';
  EXEC @ProcedureName 42;
  EXEC @ProcedureName 17;

  SELECT [_id__] AS CallNumber, [_id_] AS ParameterValue
    INTO #Actual FROM SpyProcedureTests.IdParameter_SpyProcedureLog;
  CREATE TABLE #Expected(CallNumber INT, ParameterValue INT);
  INSERT INTO #Expected VALUES(1,42),(2,17);
  EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';
END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure avoids repeated identity column name collisions]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.IdParameter @_id_ INT, @_id__ INT AS RETURN;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.IdParameter';

  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.IdParameter';
  EXEC @ProcedureName 42, 17;

  SELECT [_id___] AS CallNumber, [_id_] AS FirstParameter, [_id__] AS SecondParameter
    INTO #Actual FROM SpyProcedureTests.IdParameter_SpyProcedureLog;
  CREATE TABLE #Expected(CallNumber INT, FirstParameter INT, SecondParameter INT);
  INSERT INTO #Expected VALUES(1,42,17);
  EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';
END;
GO
CREATE PROC SpyProcedureTests.[test cursor parameter names do not rename the log identity column]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.IdParameter @_id_ CURSOR VARYING OUTPUT AS RETURN;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.IdParameter';

  DECLARE @C CURSOR;
  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.IdParameter';
  EXEC @ProcedureName @C;

  DECLARE @Actual INT = (SELECT [_id_] FROM SpyProcedureTests.IdParameter_SpyProcedureLog);
  EXEC tSQLt.AssertEquals @Expected = 1, @Actual = @Actual;
END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure should allow NULL values for sysname parms]
AS
BEGIN
  EXEC('CREATE PROC dbo.InnerProcedure @P1 sysname ' +
       'AS EXEC tSQLt.Fail ''InnerProcedure was executed '',@P1;');

  EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

  DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure NULL;

  SELECT P1
    INTO #Actual
    FROM dbo.InnerProcedure_SpyProcedureLog;

  SELECT TOP(0) *
    INTO #Expected
    FROM #Actual;

  INSERT INTO #Expected(P1) VALUES(NULL);
  
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure should allow NULL values for user defined types created as not nullable]
AS
BEGIN
  EXEC ('CREATE TYPE SpyProcedureTests.MyType FROM INT NOT NULL;');
  
  EXEC('CREATE PROC dbo.InnerProcedure @P1 SpyProcedureTests.MyType ' +
       'AS EXEC tSQLt.Fail ''InnerProcedure was executed '',@P1;');

  EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';

  DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
  EXEC @InnerProcedure NULL;

  SELECT P1
    INTO #Actual
    FROM dbo.InnerProcedure_SpyProcedureLog;

  SELECT TOP(0) *
    INTO #Expected
    FROM #Actual;

  INSERT INTO #Expected(P1) VALUES(NULL);
  
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure should log call when output parameters are present]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(100) OUT AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';
    
    DECLARE @ActualOutputValue VARCHAR(100);
    
    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure @P1 = @ActualOutputValue OUT;
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog
                   WHERE P1 IS NULL)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure should log values of output parameters if input was provided for them]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(100) OUT AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';
    
    DECLARE @ActualOutputValue VARCHAR(100);
    SET @ActualOutputValue = 'HELLO';
    
    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure @P1 = @ActualOutputValue OUT;
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog
                   WHERE P1 = 'HELLO')
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure should log values if a mix of input an output parameters are provided]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(100) OUT, @P2 INT, @P3 BIT OUT AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';
    
    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure @P1 = 'PARAM1', @P2 = 2, @P3 = 0;
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog
                   WHERE P1 = 'PARAM1'
                     AND P2 = 2
                     AND P3 = 0)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure should not log the default values of parameters if no value is provided]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(100) = ''MY DEFAULT'' AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';
    
    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure;
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog
                   WHERE P1 IS NULL)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure can be given a command to execute]
AS
BEGIN
    EXEC ('CREATE PROC dbo.InnerProcedure AS EXEC tSQLt.Fail ''InnerProcedure was executed'';');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure', 'RETURN 1';
    
    DECLARE @ReturnVal INT;
    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @ReturnVal = @InnerProcedure;
    
    IF NOT EXISTS(SELECT 1 FROM dbo.InnerProcedure_SpyProcedureLog)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged!';
    END;
    
    EXEC tSQLt.AssertEquals 1, @ReturnVal;
END;
GO

CREATE PROC SpyProcedureTests.[test command given to SpyProcedure can be used to set output parameters]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 VARCHAR(100) OUT AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');
    
    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure', 'SET @P1 = ''HELLO'';';
    
    DECLARE @ActualOutputValue VARCHAR(100);
    
    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure @P1 = @ActualOutputValue OUT;
    
    EXEC tSQLt.AssertEqualsString 'HELLO', @ActualOutputValue;
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog
                   WHERE P1 IS NULL)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure can have a cursor output parameter]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @P1 CURSOR VARYING OUTPUT AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure';
    
    DECLARE @OutputCursor CURSOR;
    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'dbo.InnerProcedure'
    EXEC @InnerProcedure @P1 = @OutputCursor OUTPUT; 
    
    IF NOT EXISTS(SELECT 1
                    FROM dbo.InnerProcedure_SpyProcedureLog)
    BEGIN
        EXEC tSQLt.Fail 'InnerProcedure call was not logged correctly!';
    END
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure raises appropriate error if the procedure does not exist]
AS
BEGIN
    DECLARE @Msg NVARCHAR(MAX); SET @Msg = 'no error';
    
    BEGIN TRY
      EXEC tSQLt.SpyProcedure 'SpyProcedureTests.DoesNotExist';
    END TRY
    BEGIN CATCH
        SET @Msg = ERROR_MESSAGE();
    END CATCH

    IF @Msg NOT LIKE '%Cannot use SpyProcedure on %DoesNotExist% because the procedure does not exist%'
    BEGIN
        EXEC tSQLt.Fail 'Expected SpyProcedure to throw a meaningful error, but message was: ', @Msg;
    END
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure raises appropriate error if the procedure name given references another type of object]
AS
BEGIN
    DECLARE @Msg NVARCHAR(MAX); SET @Msg = 'no error';
    
    BEGIN TRY
      CREATE TABLE SpyProcedureTests.dummy (i int);
      EXEC tSQLt.SpyProcedure 'SpyProcedureTests.dummy';
    END TRY
    BEGIN CATCH
        SET @Msg = ERROR_MESSAGE();
    END CATCH

    IF @Msg NOT LIKE '%Cannot use SpyProcedure on %dummy% because the procedure does not exist%'
    BEGIN
        EXEC tSQLt.Fail 'Expected SpyProcedure to throw a meaningful error, but message was: ', @Msg;
    END
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure handles procedure names with spaces]
AS
BEGIN
    DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

    EXEC('CREATE PROC SpyProcedureTests.[Spyee Proc] AS RETURN 0;');

    EXEC tSQLt.SpyProcedure 'SpyProcedureTests.[Spyee Proc]';
    
    DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'SpyProcedureTests.[Spyee Proc]'
    EXEC @InnerProcedure;
    
    SELECT *
      INTO #Actual
      FROM SpyProcedureTests.[Spyee Proc_SpyProcedureLog];
    
    SELECT 1 _id_
      INTO #Expected
     WHERE 0=1;

    INSERT #Expected
    SELECT 1;
    
    EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure handles procedure and schema names with single quotes]
AS
BEGIN
  DECLARE @ErrorRaised INT; SET @ErrorRaised = 0;

  EXEC('CREATE SCHEMA [Tes''tSchema];');
  EXEC('CREATE PROC [Tes''tSchema].[Spye''e Proc] @testParam1 INT AS RETURN 0;');

  EXEC tSQLt.SpyProcedure '[Tes''tSchema].[Spye''e Proc]';
    
  DECLARE @InnerProcedure VARCHAR(MAX) = '[Tes''tSchema].[Spye''e Proc]';
  EXEC @InnerProcedure 27;
  
  SELECT testParam1
    INTO #Actual
    FROM [Tes'tSchema].[Spye'e Proc_SpyProcedureLog];

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES(27);
    
  EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure calls tSQLt.Private_RenameObjectToUniqueName on original proc]
AS
BEGIN
    DECLARE @ErrorRaised NVARCHAR(MAX); SET @ErrorRaised = 'No Error Raised';
    
    EXEC('CREATE PROC SpyProcedureTests.SpyeeProc AS RETURN 0;');

    EXEC tSQLt.SpyProcedure 'tSQLt.Private_RenameObjectToUniqueName','RAISERROR(''Intentional Error'', 16, 10)';
    
    BEGIN TRY
        EXEC tSQLt.SpyProcedure  'SpyProcedureTests.SpyeeProc';
    END TRY
    BEGIN CATCH
        SET @ErrorRaised = ERROR_MESSAGE();
    END CATCH
    
    EXEC tSQLt.AssertEqualsString 'Intentional Error', @ErrorRaised;
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure works if spyee has 100 parameters with 8000 bytes each]
AS
BEGIN
  IF OBJECT_ID('dbo.InnerProcedure') IS NOT NULL DROP PROCEDURE dbo.InnerProcedure;
  DECLARE @Cmd VARCHAR(MAX);
  SELECT @Cmd = 'CREATE PROC dbo.InnerProcedure('+
                (SELECT CASE WHEN no = 1 THEN '' ELSE ',' END +'@P'+CAST(no AS VARCHAR)+' CHAR(8000)' [text()]
                   FROM tSQLt.F_Num(100)
                    FOR XML PATH('')
                )+
                ') AS BEGIN RETURN 0; END;';
  EXEC(@Cmd);

  SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
    INTO #ExpectedM
    FROM sys.parameters
   WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

  EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'

  SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
    INTO #ActualM
    FROM sys.parameters
   WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

  SELECT * 
    INTO #Actual1
    FROM #ActualM
   WHERE parameter_id<511;
  SELECT * 
    INTO #Expected1
    FROM #ExpectedM
   WHERE parameter_id<511;
   
  EXEC tSQLt.AssertEqualsTable '#Expected1','#Actual1';

  SELECT * 
    INTO #Actual2
    FROM #ActualM
   WHERE parameter_id>510;
  SELECT * 
    INTO #Expected2
    FROM #ExpectedM
   WHERE parameter_id>510;
   
  EXEC tSQLt.AssertEqualsTable '#Expected2','#Actual2';
END
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure creates char parameters correctly]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure(
             @CHAR1 CHAR(1),
             @CHAR8000 CHAR(8000),
             @VARCHAR1 VARCHAR(1),
             @VARCHAR8000 VARCHAR(8000),
             @VARCHARMAX VARCHAR(MAX)
          )
          AS BEGIN RETURN 0; END');
    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Expected
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'

    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Actual
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure creates binary parameters correctly]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure(
             @BINARY1 BINARY(1) =NULL,
             @BINARY4000 BINARY(3000) =NULL,
             @VARBINARY1 VARBINARY(1) =NULL,
             @VARBINARY4000 VARBINARY(3000) =NULL,
             @VARBINARYMAX VARBINARY(MAX) =NULL
          )
          AS BEGIN RETURN 0; END');
    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Expected
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'

    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Actual
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

     EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';
END;
GO

CREATE PROC SpyProcedureTests.[test SpyProcedure creates log which handles binary columns]
AS
BEGIN
    DECLARE @proc NVARCHAR(100); SET @proc = 'dbo.InnerProcedure';
    EXEC('CREATE PROC dbo.InnerProcedure(
             @VARBINARY8000 VARBINARY(8000) =NULL
          )
          AS BEGIN RETURN 0; END');


    EXEC tSQLt.SpyProcedure @proc;
     
    EXEC @proc @VARBINARY8000=0x111122223333444455556666777788889999;

    DECLARE @Actual VARBINARY(8000);
    SELECT @Actual = VARBINARY8000 FROM dbo.InnerProcedure_SpyProcedureLog;
    
    EXEC tSQLt.AssertEquals 0x111122223333444455556666777788889999, @Actual;
END;
GO


CREATE PROC SpyProcedureTests.[test SpyProcedure creates nchar parameters correctly]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure(
             @NCHAR1 NCHAR(1),
             @NCHAR4000 NCHAR(4000),
             @NVARCHAR1 NVARCHAR(1),
             @NVARCHAR4000 NVARCHAR(4000),
             @NVARCHARMAX NVARCHAR(MAX)
          )
          AS BEGIN RETURN 0; END');
    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Expected
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'

    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Actual
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure creates other parameters correctly]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure(
             @TINYINT TINYINT,
             @SMALLINT SMALLINT,
             @INT INT,
             @BIGINT BIGINT
          )
          AS BEGIN RETURN 0; END');
    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Expected
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'

    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Actual
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure handles length, precision, and scale correctly]
  AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure(
             @LENGTH1 VARCHAR(42) ,
             @LENGTH2 VARCHAR(MAX) ,
             @PRECISION_SCALE NUMERIC(21, 13) 
          )
          AS BEGIN RETURN 0; END');
    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Expected
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.SpyProcedure 'dbo.InnerProcedure'

    SELECT name, parameter_id, system_type_id, user_type_id, max_length, precision, scale 
      INTO #Actual
      FROM sys.parameters
     WHERE object_id = OBJECT_ID('dbo.InnerProcedure');

    EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure fails with error if spyee has more than 1020 parameters]
AS
BEGIN
  IF OBJECT_ID('dbo.Spyee') IS NOT NULL DROP PROCEDURE dbo.Spyee;
  DECLARE @Cmd VARCHAR(MAX);
  SELECT @Cmd = 'CREATE PROC dbo.Spyee('+
                (SELECT CASE WHEN no = 1 THEN '' ELSE ',' END +'@P'+CAST(no AS VARCHAR)+' INT' [text()]
                   FROM tSQLt.F_Num(1021)
                    FOR XML PATH('')
                )+
                ') AS BEGIN RETURN 0; END;';
  EXEC(@Cmd);
  DECLARE @Err VARCHAR(MAX);SET @Err = 'NO ERROR';
  BEGIN TRY
    EXEC tSQLt.SpyProcedure 'dbo.Spyee';
  END TRY
  BEGIN CATCH
    SET @Err = ERROR_MESSAGE();
  END CATCH
  
  IF @Err NOT LIKE '%dbo.Spyee%' AND @Err NOT LIKE '%1020 parameters%'
  BEGIN
      EXEC tSQLt.Fail 'Unexpected error message was: ', @Err;
  END;
  
END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure works on procedure if type with same name exists]
AS
BEGIN
   CREATE TYPE SpyProcedureTests.ProcedureAndType FROM BIGINT;
   EXEC('CREATE PROC SpyProcedureTests.ProcedureAndType AS RETURN;');

   EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.ProcedureAndType';

   EXEC ('EXEC SpyProcedureTests.ProcedureAndType');

   SELECT _id_
     INTO #Actual
     FROM SpyProcedureTests.ProcedureAndType_SpyProcedureLog;

   SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
   
   INSERT INTO #Expected
   VALUES(1);

   EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure works on procedure if table type with same name exists]
AS
BEGIN
   CREATE TYPE SpyProcedureTests.ProcedureAndType AS TABLE(id INT);
   EXEC('CREATE PROC SpyProcedureTests.ProcedureAndType AS RETURN;');
--SELECT OBJECT_ID('SpyProcedureTests.ProcedureAndType'),TYPE_ID('SpyProcedureTests.ProcedureAndType');
   EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.ProcedureAndType';

   EXEC ('EXEC SpyProcedureTests.ProcedureAndType');

   SELECT _id_
     INTO #Actual
     FROM SpyProcedureTests.ProcedureAndType_SpyProcedureLog;

   SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
   
   INSERT INTO #Expected
   VALUES(1);

   EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE TYPE SpyProcedureTests.TableType1001 AS TABLE(SomeInt INT, SomeVarChar VARCHAR(10));
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure preserves long qualified alias type names]
AS
BEGIN
  DECLARE @TypeName sysname = REPLICATE('T', 123) + ']';
  DECLARE @QualifiedTypeName NVARCHAR(MAX) = 'SpyProcedureTests.' + QUOTENAME(@TypeName);
  EXEC('CREATE TYPE ' + @QualifiedTypeName + ' FROM INT;');
  EXEC('CREATE PROCEDURE SpyProcedureTests.LongType @P1 ' + @QualifiedTypeName + ' AS RETURN;');

  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.LongType';
  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.LongType';
  EXEC @ProcedureName 42;

  DECLARE @Actual INT = (SELECT P1 FROM SpyProcedureTests.LongType_SpyProcedureLog);
  EXEC tSQLt.AssertEquals @Expected = 42, @Actual = @Actual;
  DECLARE @ExpectedType INT = TYPE_ID(@QualifiedTypeName);
  DECLARE @ActualType INT = (SELECT user_type_id FROM sys.parameters WHERE object_id = OBJECT_ID(@ProcedureName) AND parameter_id = 1);
  EXEC tSQLt.AssertEquals @Expected = @ExpectedType, @Actual = @ActualType;
END;
GO
DECLARE @LongTableTypeName NVARCHAR(MAX) = 'SpyProcedureTests.' + QUOTENAME(REPLICATE('T', 124));
EXEC('CREATE TYPE ' + @LongTableTypeName + ' AS TABLE(A INT);');
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure preserves long qualified table type names]
AS
BEGIN
  DECLARE @TypeName sysname = REPLICATE('T', 124);
  DECLARE @QualifiedTypeName NVARCHAR(MAX) = 'SpyProcedureTests.' + QUOTENAME(@TypeName);
  EXEC('CREATE PROCEDURE SpyProcedureTests.LongType @P1 ' + @QualifiedTypeName + ' READONLY AS RETURN;');

  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.LongType';
  EXEC('DECLARE @P1 ' + @QualifiedTypeName + '; INSERT INTO @P1 VALUES(42);
        EXEC SpyProcedureTests.LongType @P1;');

  DECLARE @Actual INT = (SELECT P1.value('(/P1/row/A)[1]','INT') FROM SpyProcedureTests.LongType_SpyProcedureLog);
  EXEC tSQLt.AssertEquals @Expected = 42, @Actual = @Actual;
END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure can have a table type parameter]
AS
BEGIN
  EXEC('CREATE PROC SpyProcedureTests.InnerProcedure @P1 SpyProcedureTests.TableType1001 READONLY AS EXEC tSQLt.Fail ''InnerProcedure was executed;''');

  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.InnerProcedure';

  DECLARE @TableParameter SpyProcedureTests.TableType1001;
  INSERT INTO @TableParameter(SomeInt,SomeVarChar)VALUES(10,'S1');
  INSERT INTO @TableParameter(SomeInt,SomeVarChar)VALUES(202,'V2');
  INSERT INTO @TableParameter(SomeInt,SomeVarChar)VALUES(3303,'C3');

  DECLARE @InnerProcedure VARCHAR(MAX);SET @InnerProcedure = 'SpyProcedureTests.InnerProcedure'
  EXEC @InnerProcedure @P1 = @TableParameter; 

  SELECT RowNode.value('SomeInt[1]','INT') SomeInt,RowNode.value('SomeVarChar[1]','VARCHAR(10)') SomeVarChar
    INTO #Actual
    FROM SpyProcedureTests.InnerProcedure_SpyProcedureLog
   CROSS APPLY P1.nodes('P1/row') AS N(RowNode);  
  
  SELECT *
  INTO #Expected
  FROM @TableParameter AS TP;
 
  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
    
END;
GO
CREATE PROC SpyProcedureTests.[test Private_GenerateCreateProcedureSpyStatement does not create log table when @LogTableName is NULL]
AS
BEGIN
    EXEC('CREATE PROC dbo.OriginalInnerProcedure AS RETURN;');

    DECLARE @ProcedureObjectId INT = OBJECT_ID('dbo.OriginalInnerProcedure');

    DECLARE @CreateProcedureStatement NVARCHAR(MAX);
    DECLARE @CreateLogTableStatement NVARCHAR(MAX);

    EXEC tSQLt.Private_GenerateCreateProcedureSpyStatement
           @ProcedureObjectId = @ProcedureObjectId,
           @OriginalProcedureName = 'dbo.OriginalInnerProcedure',
           @LogTableName = NULL,
           @CommandToExecute = NULL,
           @CallOriginal = 0,
           @CreateProcedureStatement = @CreateProcedureStatement OUT,
           @CreateLogTableStatement = @CreateLogTableStatement OUT;

    EXEC tSQLt.AssertEqualsString @Expected = NULL, @Actual = @CreateLogTableStatement;     
END;
GO
GO
CREATE PROC SpyProcedureTests.[test Private_CreateProcedureSpy does create spy when @LogTableName is NULL]
AS
BEGIN
    EXEC('CREATE PROC dbo.OriginalInnerProcedure AS RETURN;'); /* This is the simulated rename of dbo.SpiedInnerProcedure */

    DECLARE @ProcedureObjectId INT = OBJECT_ID('dbo.OriginalInnerProcedure');

    DECLARE @CreateProcedureStatement NVARCHAR(MAX);
    DECLARE @CreateLogTableStatement NVARCHAR(MAX);

    EXEC tSQLt.Private_GenerateCreateProcedureSpyStatement
           @ProcedureObjectId = @ProcedureObjectId,
           @OriginalProcedureName = 'dbo.SpiedInnerProcedure',
           @LogTableName = NULL,
           @CommandToExecute = NULL,
           @CallOriginal = 0,
           @CreateProcedureStatement = @CreateProcedureStatement OUT,
           @CreateLogTableStatement = @CreateLogTableStatement OUT;

    EXEC(@CreateProcedureStatement);

    EXEC tSQLt.AssertObjectExists @ObjectName = 'dbo.SpiedInnerProcedure';     

END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure works with CLR procedures]
AS
BEGIN
    EXEC('CREATE PROC dbo.InnerProcedure @expectedCommand NVARCHAR(MAX), @actualCommand NVARCHAR(MAX) AS EXTERNAL NAME tSQLtCLR.[tSQLtCLR.StoredProcedures].AssertResultSetsHaveSameMetaData;');
    
    EXEC tSQLt.SpyProcedure @ProcedureName = 'dbo.InnerProcedure';

    DECLARE @ProcName NVARCHAR(MAX) = 'dbo.InnerProcedure';
    EXEC @ProcName @expectedCommand = 'Select 1 [Int]', @actualCommand = 'Select ''c'' [char]';

    SELECT expectedCommand, actualCommand INTO #Actual FROM dbo.InnerProcedure_SpyProcedureLog;
    SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
    INSERT INTO #Expected
    VALUES('Select 1 [Int]', 'Select ''c'' [char]');

    EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
    
END;
GO
CREATE PROC SpyProcedureTests.[test new Procedure Spy is marked as tSQLt.IsTempObject]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 AS RETURN;');
  
  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1';
  
  SELECT name, value 
    INTO #Actual
    FROM sys.extended_properties
   WHERE class_desc = 'OBJECT_OR_COLUMN'
     AND major_id = OBJECT_ID('SpyProcedureTests.TempProcedure1')
     AND name = 'tSQLt.IsTempObject';

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  
  INSERT INTO #Expected VALUES('tSQLt.IsTempObject',	1);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
CREATE PROC SpyProcedureTests.[test SpyProcedure calls tSQLt.Private_MarktSQLtTempObject on new objects]
AS
BEGIN
  DECLARE @OriginalObjectId INT = OBJECT_ID('tSQLt.Private_MarktSQLtTempObject');

  EXEC tSQLt.SpyProcedure @ProcedureName = '[tSQLt].[Private_MarktSQLtTempObject]';
  --We are testing that SpyProcedure calls this ^^ after spying this ^^, so this line serves as prep and action.

  SELECT ObjectName, ObjectType, NewNameOfOriginalObject 
    INTO #Actual 
    FROM tSQLt.Private_MarktSQLtTempObject_SpyProcedureLog;
  
  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected
    VALUES('[tSQLt].[Private_MarktSQLtTempObject]', N'PROCEDURE', OBJECT_NAME(@OriginalObjectId)),
          ('[tSQLt].[Private_MarktSQLtTempObject_SpyProcedureLog]', N'TABLE', NULL);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
  
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test new SpyProcedureLog table is marked as tSQLt.IsTempObject]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 AS RETURN;');
  
  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1';
  
  SELECT name, value 
    INTO #Actual
    FROM sys.extended_properties
   WHERE class_desc = 'OBJECT_OR_COLUMN'
     AND major_id = OBJECT_ID('SpyProcedureTests.TempProcedure1_SpyProcedureLog')
     AND name = 'tSQLt.IsTempObject';

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  
  INSERT INTO #Expected VALUES('tSQLt.IsTempObject',	1);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test can handle existing SpyProcedureLog table]
AS
BEGIN
  CREATE TABLE SpyProcedureTests.TempProcedure1_SpyProcedureLog ([Please don't do this] INT, [but just in case, we can handle it] NVARCHAR(MAX));
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 AS RETURN;');

  EXEC tSQLt.ExpectNoException;
    
  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1';  
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test calls the original procedure if @CallOriginal = 1]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 AS BEGIN INSERT INTO #Actual VALUES (''SpyProcedureTests.TempProcedure1 called''); END;');

  CREATE TABLE #Actual (Id INT IDENTITY (1,1), Msg NVARCHAR(MAX));

  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1', @CallOriginal = 1;

  EXEC('SpyProcedureTests.TempProcedure1');

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES(1,'SpyProcedureTests.TempProcedure1 called');

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test does not call the original procedure if @CallOriginal = 0]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 AS BEGIN INSERT INTO #Actual VALUES (''SpyProcedureTests.TempProcedure1 called''); END;');

  CREATE TABLE #Actual (Id INT IDENTITY (1,1), Msg NVARCHAR(MAX));

  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1', @CallOriginal = 0;

  EXEC('SpyProcedureTests.TempProcedure1');

  EXEC tSQLt.AssertEmptyTable '#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test does not call the original procedure if @CallOriginal = NULL]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 AS BEGIN INSERT INTO #Actual VALUES (''SpyProcedureTests.TempProcedure1 called''); END;');

  CREATE TABLE #Actual (Id INT IDENTITY (1,1), Msg NVARCHAR(MAX));

  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1', @CallOriginal = NULL;

  EXEC('SpyProcedureTests.TempProcedure1');

  EXEC tSQLt.AssertEmptyTable '#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test does not call the original procedure if @CallOriginal is not specified]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 AS BEGIN INSERT INTO #Actual VALUES (''SpyProcedureTests.TempProcedure1 called''); END;');

  CREATE TABLE #Actual (Id INT IDENTITY (1,1), Msg NVARCHAR(MAX));

  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1';

  EXEC('SpyProcedureTests.TempProcedure1');

  EXEC tSQLt.AssertEmptyTable '#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test calls the original procedure if @CallOriginal = 1 even if schema or procedure name require quoting]
AS
BEGIN
  EXEC('CREATE SCHEMA [Inner Test Schema];');
  EXEC('CREATE PROCEDURE [Inner Test Schema].[Temp Procedure 1] AS BEGIN INSERT INTO #Actual VALUES (''[Inner Test Schema].[Temp Procedure 1] called''); END;');

  CREATE TABLE #Actual (Id INT IDENTITY (1,1), Msg NVARCHAR(MAX));

  EXEC tSQLt.SpyProcedure @ProcedureName = '[Inner Test Schema].[Temp Procedure 1]', @CallOriginal = 1;

  EXEC('[Inner Test Schema].[Temp Procedure 1]');

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES(1,'[Inner Test Schema].[Temp Procedure 1] called');

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO

CREATE PROC SpyProcedureTests.[test calls original procedure with parameters if @CallOriginal = 1]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 @AnInt INT, @AString NVARCHAR(MAX) AS BEGIN INSERT INTO #Actual VALUES (''SpyProcedureTests.TempProcedure1(''+CAST(@AnInt AS NVARCHAR(MAX))+'',''+@AString+'') called''); END;');

  CREATE TABLE #Actual (Id INT IDENTITY (1,1), Msg NVARCHAR(MAX));

  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1', @CallOriginal = 1;

  EXEC('EXEC SpyProcedureTests.TempProcedure1 42,''XYZ'';');

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES(1,'SpyProcedureTests.TempProcedure1(42,XYZ) called');

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test calls original procedure with OUTPUT parameters if @CallOriginal = 1]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 @AnInt INT OUTPUT, @AString NVARCHAR(MAX) OUTPUT AS BEGIN SELECT @AnInt = 8383, @AString = ''424242''; END;');


  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1', @CallOriginal = 1;

  DECLARE @InputOutputInt INT = -17;
  DECLARE @InputOutputString NVARCHAR(MAX) = '007';
  DECLARE @ProcedureNameVariableSoWeDoNotGetAWarning NVARCHAR(MAX) = 'SpyProcedureTests.TempProcedure1';
  EXEC @ProcedureNameVariableSoWeDoNotGetAWarning @InputOutputInt OUT, @InputOutputString OUT;

  SELECT @InputOutputInt AS AnInt, @InputOutputString AS AString INTO #Actual;

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES(8383, '424242');

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test CallOriginal returns an output cursor]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.ReturnCursor @C CURSOR VARYING OUTPUT AS
        BEGIN SET @C = CURSOR LOCAL STATIC FOR SELECT 42; OPEN @C; END;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.ReturnCursor', @CallOriginal = 1;

  DECLARE @C CURSOR;
  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.ReturnCursor';
  EXEC @ProcedureName @C OUTPUT;

  DECLARE @Status INT = CURSOR_STATUS('variable', '@C');
  EXEC tSQLt.AssertEquals @Expected = 1, @Actual = @Status;
  DECLARE @Actual INT;
  FETCH NEXT FROM @C INTO @Actual;
  CLOSE @C;
  DEALLOCATE @C;
  EXEC tSQLt.AssertEquals @Expected = 42, @Actual = @Actual;
END;
GO
CREATE PROC SpyProcedureTests.[test CallOriginal returns both an output cursor and return status without variable collisions]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.ReturnCursor @C CURSOR VARYING OUTPUT, @SpyProcedureReturnValue INT AS
        BEGIN SET @C = CURSOR LOCAL STATIC FOR SELECT @SpyProcedureReturnValue; OPEN @C; RETURN -37; END;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.ReturnCursor',
       @CommandToExecute = 'DECLARE @SpyProcedureReturnValue1 INT;', @CallOriginal = 1;

  DECLARE @C CURSOR;
  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.ReturnCursor';
  DECLARE @ReturnStatus INT;
  EXEC @ReturnStatus = @ProcedureName @C OUTPUT, 42;

  DECLARE @Status INT = CURSOR_STATUS('variable', '@C');
  EXEC tSQLt.AssertEquals @Expected = 1, @Actual = @Status;
  DECLARE @Actual INT;
  FETCH NEXT FROM @C INTO @Actual;
  CLOSE @C;
  DEALLOCATE @C;
  EXEC tSQLt.AssertEquals @Expected = 42, @Actual = @Actual;
  EXEC tSQLt.AssertEquals @Expected = -37, @Actual = @ReturnStatus;
END;
GO
CREATE PROC SpyProcedureTests.[test CallOriginal returns an empty output cursor]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.ReturnCursor @C CURSOR VARYING OUTPUT AS
        BEGIN SET @C = CURSOR LOCAL STATIC FOR SELECT 42 WHERE 1 = 0; OPEN @C; END;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.ReturnCursor', @CallOriginal = 1;

  DECLARE @C CURSOR;
  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.ReturnCursor';
  EXEC @ProcedureName @C OUTPUT;

  DECLARE @Status INT = CURSOR_STATUS('variable', '@C');
  EXEC tSQLt.AssertEquals @Expected = 0, @Actual = @Status;
  CLOSE @C;
  DEALLOCATE @C;
END;
GO
CREATE PROC SpyProcedureTests.[test calls original procedure with cursor parameters if @CallOriginal = 1]
AS
BEGIN
  EXEC('
    CREATE PROCEDURE SpyProcedureTests.TempProcedure1 @Cursor1 CURSOR VARYING OUTPUT, @NotACursor INT, @Cursor2 CURSOR VARYING OUTPUT
    AS 
    BEGIN 
      DECLARE @FirstInt INT;
      DECLARE @SecondInt INT;
      OPEN @Cursor1; 
        FETCH NEXT FROM @Cursor1 INTO @FirstInt;
      CLOSE @Cursor1; 
      DEALLOCATE @Cursor1;
      OPEN @Cursor2; 
        FETCH NEXT FROM @Cursor2 INTO @SecondInt;
      CLOSE @Cursor2; 
      DEALLOCATE @Cursor2;
      INSERT INTO #Actual VALUES(@FirstInt, @SecondInt, @NotACursor);
    END;'
  );
  CREATE TABLE #Actual (intA INT, intB INT, intC INT);

  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1', @CallOriginal = 1;

  DECLARE @InputOnlyInt INT = 17;
  DECLARE @Cursor11 CURSOR; SET @Cursor11 = CURSOR FOR SELECT 36;
  DECLARE @Cursor22 CURSOR; SET @Cursor22 = CURSOR FOR SELECT 42; 
  DECLARE @ProcedureNameVariableSoWeDoNotGetAWarning NVARCHAR(MAX) = 'SpyProcedureTests.TempProcedure1';

  EXEC @ProcedureNameVariableSoWeDoNotGetAWarning @Cursor11, @InputOnlyInt, @Cursor22;

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES(36, 42, 17);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE TYPE SpyProcedureTests.Type1 AS TABLE(A INT);
GO
CREATE PROC SpyProcedureTests.[test CallOriginal supports mixed cursor directions with scalar and table parameters]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.MixedCursors
          @InputCursor CURSOR VARYING OUTPUT, @OutputCursor CURSOR VARYING OUTPUT,
          @SpyProcedureCursorValue INT OUTPUT, @Rows SpyProcedureTests.Type1 READONLY
        AS BEGIN
          OPEN @InputCursor;
          FETCH NEXT FROM @InputCursor INTO @SpyProcedureCursorValue;
          CLOSE @InputCursor;
          SET @OutputCursor = CURSOR LOCAL STATIC FOR SELECT @SpyProcedureCursorValue + A FROM @Rows;
          OPEN @OutputCursor;
        END;');
  EXEC tSQLt.SpyProcedure 'SpyProcedureTests.MixedCursors',
       @CommandToExecute = 'DECLARE @SpyProcedureCursorCommand NVARCHAR(MAX);', @CallOriginal = 1;

  DECLARE @InputCursor CURSOR;
  SET @InputCursor = CURSOR LOCAL STATIC FOR SELECT 17;
  DECLARE @OutputCursor CURSOR;
  DECLARE @Value INT = -1;
  DECLARE @Rows SpyProcedureTests.Type1;
  INSERT INTO @Rows VALUES(25);
  DECLARE @ProcedureName NVARCHAR(MAX) = 'SpyProcedureTests.MixedCursors';
  EXEC @ProcedureName @InputCursor, @OutputCursor OUTPUT, @Value OUTPUT, @Rows;

  DECLARE @Status INT = CURSOR_STATUS('variable', '@OutputCursor');
  EXEC tSQLt.AssertEquals @Expected = 1, @Actual = @Status;
  DECLARE @Actual INT;
  FETCH NEXT FROM @OutputCursor INTO @Actual;
  CLOSE @OutputCursor;
  DEALLOCATE @OutputCursor;
  DEALLOCATE @InputCursor;
  EXEC tSQLt.AssertEquals @Expected = 17, @Actual = @Value;
  EXEC tSQLt.AssertEquals @Expected = 42, @Actual = @Actual;
END;
GO
CREATE PROC SpyProcedureTests.[test calls original procedure with table valued parameters if @CallOriginal = 1]
AS
BEGIN
  EXEC('
    CREATE PROCEDURE SpyProcedureTests.TempProcedure1 @Table1 SpyProcedureTests.Type1 READONLY, @NotATable INT, @Table2 SpyProcedureTests.Type1 READONLY
    AS 
    BEGIN 
      DECLARE @FirstInt INT = (SELECT A FROM @Table1);
      DECLARE @SecondInt INT = (SELECT A FROM @Table2);
      INSERT INTO #Actual VALUES(@FirstInt, @SecondInt, @NotATable);
    END;'
  );
  CREATE TABLE #Actual (intA INT, intB INT, intC INT);

  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1', @CallOriginal = 1;

  EXEC('
    DECLARE @InputOnlyInt INT = 17;
    DECLARE @Table11 AS SpyProcedureTests.Type1; INSERT INTO @Table11 VALUES(36);
    DECLARE @Table22 AS SpyProcedureTests.Type1; INSERT INTO @Table22 VALUES(42);
  
    DECLARE @ProcedureNameVariableSoWeDoNotGetAWarning NVARCHAR(MAX) = ''SpyProcedureTests.TempProcedure1'';
    EXEC @ProcedureNameVariableSoWeDoNotGetAWarning @Table11, @InputOnlyInt, @Table22;
  ');
  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES(36, 42, 17);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test calls the original procedure after @CommandToExecute if @CallOriginal = 1]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 AS BEGIN INSERT INTO #Actual VALUES (''SpyProcedureTests.TempProcedure1 called''); END;');

  CREATE TABLE #Actual (Id INT IDENTITY (1,1), Msg NVARCHAR(MAX));

  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1', @CommandToExecute='INSERT INTO #Actual VALUES (''CommandToExecute called'');', @CallOriginal = 1;

  EXEC('SpyProcedureTests.TempProcedure1');

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES(1,'CommandToExecute called'),(2,'SpyProcedureTests.TempProcedure1 called');

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test @SpyProcedureOriginalObjectName contains original proc name inside spy]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 @I INT = NULL AS BEGIN INSERT INTO #Actual VALUES (''SpyProcedureTests.TempProcedure1 called'', @I); END;');

  CREATE TABLE #Actual (Id INT IDENTITY (1,1), Msg NVARCHAR(MAX), I INT);

  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1', @CommandToExecute='EXEC @SpyProcedureOriginalObjectName 42;';

  EXEC('SpyProcedureTests.TempProcedure1');

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES(1,'SpyProcedureTests.TempProcedure1 called',42);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test @SpyProcedureOriginalObjectName contains original proc name inside spy even if quoting is required]
AS
BEGIN
  EXEC('CREATE SCHEMA [Inner Test.Schema 1];');
  EXEC('CREATE PROCEDURE [Inner Test.Schema 1].[Temp Proc.edure 1] @I INT = NULL AS BEGIN INSERT INTO #Actual VALUES (''[Inner Test.Schema 1].[Temp Proc.edure 1] called'', @I); END;');

  CREATE TABLE #Actual (Id INT IDENTITY (1,1), Msg NVARCHAR(MAX), I INT);

  EXEC tSQLt.SpyProcedure @ProcedureName = '[Inner Test.Schema 1].[Temp Proc.edure 1]', @CommandToExecute='EXEC @SpyProcedureOriginalObjectName 42;';

  EXEC('[Inner Test.Schema 1].[Temp Proc.edure 1]');

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES(1,'[Inner Test.Schema 1].[Temp Proc.edure 1] called',42);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test @SpyProcedureOriginalObjectName contains original proc name even if it has single quotes, dots, or spaces]
AS
BEGIN
  EXEC('CREATE SCHEMA [I''nn''er Test.Schema 1];');
  EXEC('CREATE PROCEDURE [I''nn''er Test.Schema 1].[T''emp Proc.edure 1] @I INT = NULL 
        AS 
        BEGIN 
          INSERT INTO #Actual VALUES (''[I''''nn''''er Test.Schema 1].[T''''emp Proc.edure 1] called'', @I); 
        END;'
      );

  CREATE TABLE #Actual (Msg NVARCHAR(MAX), I INT);

  EXEC tSQLt.SpyProcedure @ProcedureName = '[I''nn''er Test.Schema 1].[T''emp Proc.edure 1]', @CommandToExecute='EXEC @SpyProcedureOriginalObjectName 42;';


  EXEC('[I''nn''er Test.Schema 1].[T''emp Proc.edure 1]');

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES('[I''nn''er Test.Schema 1].[T''emp Proc.edure 1] called',42);

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO
CREATE PROC SpyProcedureTests.[test calls the original procedure even if @CommandToExecute contains inline comment]
AS
BEGIN
  EXEC('CREATE PROCEDURE SpyProcedureTests.TempProcedure1 AS BEGIN INSERT INTO #Actual VALUES (''SpyProcedureTests.TempProcedure1 called''); END;');

  CREATE TABLE #Actual (Id INT IDENTITY (1,1), Msg NVARCHAR(MAX));

  EXEC tSQLt.SpyProcedure @ProcedureName = 'SpyProcedureTests.TempProcedure1', @CommandToExecute='DECLARE @II INT = 1;--PRINT @II;', @CallOriginal = 1;

  EXEC('SpyProcedureTests.TempProcedure1');

  SELECT TOP(0) A.* INTO #Expected FROM #Actual A RIGHT JOIN #Actual X ON 1=0;
  INSERT INTO #Expected VALUES(1,'SpyProcedureTests.TempProcedure1 called');

  EXEC tSQLt.AssertEqualsTable '#Expected','#Actual';
END;
GO
/*-----------------------------------------------------------------------------------------------*/
GO

