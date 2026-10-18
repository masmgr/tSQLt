GO
EXEC tSQLt.NewTestClass 'AssertEqualsTableByKeyTests';
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test empty tables and reordered rows compare equal]
AS
BEGIN
  CREATE TABLE #E(Id INT, Val NVARCHAR(30));
  CREATE TABLE #A(Val NVARCHAR(30), Id INT, Extra XML);
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
  INSERT #E VALUES(1,N'one'),(2,N'two');
  INSERT #A VALUES(N'two',2,NULL),(N'one',1,NULL);
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
  DECLARE @Count INT;
  SELECT @Count=COUNT(*) FROM #E;
  EXEC tSQLt.AssertEquals 2,@Count;
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test composite nullable keys match and key only tables work]
AS
BEGIN
  CREATE TABLE #E(Id INT, Line INT);
  CREATE TABLE #A(Id INT, Line INT);
  INSERT #E VALUES(NULL,NULL),(1,NULL),(NULL,1),(1,1);
  INSERT #A SELECT * FROM #E;
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A',' Line , [Id] ';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test changed missing and extra rows have exact diagnostics]
AS
BEGIN
  CREATE TABLE #E(Id INT, Z NVARCHAR(20), A INT);
  CREATE TABLE #A(Id INT, Z NVARCHAR(20), A INT);
  INSERT #E VALUES(1,N'old',NULL),(2,N'missing',1);
  INSERT #A VALUES(1,NULL,5),(3,N'extra',2);
  CREATE TABLE #Diff([Key1: Id] INT,DifferenceType NVARCHAR(10),ColumnName NVARCHAR(128),ExpectedValue NVARCHAR(MAX),ActualValue NVARCHAR(MAX));
  INSERT #Diff VALUES(1,N'Changed',N'Z',N'old',NULL),(1,N'Changed',N'A',NULL,N'5'),
    (2,N'Missing',NULL,N'<present>',N'<missing>'),(3,N'Extra',NULL,N'<missing>',N'<present>');
  DECLARE @Expected NVARCHAR(MAX);
  EXEC tSQLt.TableToText @txt=@Expected OUTPUT,@TableName='#Diff',@OrderBy='[Key1: Id],DifferenceType,CASE ColumnName WHEN ''Z'' THEN 1 ELSE 2 END';
  SET @Expected=N'context'+CHAR(13)+CHAR(10)+N'Unexpected/missing resultset rows or changed column values!'+CHAR(13)+CHAR(10)+@Expected;
  EXEC tSQLt_testutil.AssertFailMessageEquals
    'EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''Id'',N''context'';',@Expected;
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test null key row presence is not inferred from key values]
AS
BEGIN
  CREATE TABLE #E(Id INT);
  CREATE TABLE #A(Id INT);
  INSERT #E VALUES(NULL);
  EXEC tSQLt_testutil.AssertFailMessageLike 'EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''Id'';',
    '%Missing%<present>%<missing>%';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test changed key is missing plus extra]
AS
BEGIN
  CREATE TABLE #E(Id INT, V INT);
  CREATE TABLE #A(Id INT, V INT);
  INSERT #E VALUES(1,10);
  INSERT #A VALUES(2,10);
  DECLARE @Msg NVARCHAR(MAX);
  EXEC tSQLt_testutil.CaptureFailMessage 'EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''Id'';',@Msg OUTPUT;
  EXEC tSQLt.AssertLike '%Missing%',@Msg;
  EXEC tSQLt.AssertLike '%Extra%',@Msg;
  IF @Msg LIKE '%|Changed%' EXEC tSQLt.Fail 'Changed keys must not be reported as column changes.';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test quoted identifiers and internal name collisions]
AS
BEGIN
  CREATE TABLE #E([a,b] INT,[x]]y] INT,[DifferenceType] INT,[Present] INT,[ColumnName] NVARCHAR(20),[K1] INT);
  CREATE TABLE #A([a,b] INT,[x]]y] INT,[DifferenceType] INT,[Present] INT,[ColumnName] NVARCHAR(20),[K1] INT);
  INSERT #E VALUES(1,2,3,4,N'日本語',5);
  INSERT #A VALUES(1,2,3,4,N'変更',5);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''[a,b], [x]]y], DifferenceType'';',
    N'%Key1: a,b%Key2: x]y%Key3: DifferenceType%Changed%ColumnName%日本語%変更%';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test expected duplicate nullable composite key is an input error]
AS
BEGIN
  CREATE TABLE #E(Id INT, Line INT, Val INT);
  CREATE TABLE #A(Id INT, Line INT, Val INT);
  INSERT #E VALUES(NULL,1,2),(NULL,1,3);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%duplicate keys in #E%NULL%1%2%',@ExpectedSeverity=16;
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id,Line';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test actual identical duplicate key is an input error]
AS
BEGIN
  CREATE TABLE #E(Id INT, Val INT);
  CREATE TABLE #A(Id INT, Val INT);
  INSERT #A VALUES(42,1),(42,1);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%duplicate keys in #A%42%2%',@ExpectedSeverity=16;
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[Assert invalid key list]
  @Keys NVARCHAR(MAX)
AS
BEGIN
  CREATE TABLE #E(Id INT);
  CREATE TABLE #A(Id INT);
  DECLARE @Error NVARCHAR(MAX);
  BEGIN TRY
    EXEC tSQLt.AssertEqualsTableByKey '#E','#A',@Keys;
  END TRY
  BEGIN CATCH
    SET @Error=ERROR_MESSAGE();
  END CATCH;
  EXEC tSQLt.AssertLike '%@KeyColumns must be a nonempty list%',@Error;
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test invalid key lists are rejected without executing SQL]
AS
BEGIN
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] NULL;
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] '';
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] ' ';
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] ',Id';
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] 'Id,';
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] 'Id, ';
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] 'Id,,Id';
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] 'Id,[Id]';
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] '[Id';
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] '[Id]x';
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] 'NoSuchColumn';
  EXEC AssertEqualsTableByKeyTests.[Assert invalid key list] 'Id]; DROP TABLE #E;--';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test missing actual column is an input error even with no rows]
AS
BEGIN
  CREATE TABLE #E(Id INT,V INT);
  CREATE TABLE #A(Id INT);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%Actual is missing a column from Expected%';
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test unsupported data types are rejected even with no rows]
AS
BEGIN
  CREATE TABLE #E(Id INT,V XML);
  CREATE TABLE #A(Id INT,V XML);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%datatype that is not supported for tSQLt.AssertEqualsTableByKey%';
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test numeric datetime and binary values retain comparison semantics]
AS
BEGIN
  CREATE TABLE #E(Id INT,N DECIMAL(18,6),D DATETIME,B VARBINARY(16),F FLOAT);
  CREATE TABLE #A(Id INT,N DECIMAL(18,6),D DATETIME,B VARBINARY(16),F FLOAT);
  INSERT #E VALUES(1,1.123456,'20200101',0x123456,1E-12);
  INSERT #A SELECT * FROM #E;
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
  UPDATE #A SET B=0xABCDEF;
  EXEC tSQLt_testutil.AssertFailMessageLike 'EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''Id'';',
    '%Changed%B%0x123456%0xABCDEF%';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test regular schema qualified tables and input preservation]
AS
BEGIN
  CREATE TABLE AssertEqualsTableByKeyTests.E(Id INT,V INT);
  CREATE TABLE AssertEqualsTableByKeyTests.A(Id INT,V INT);
  INSERT AssertEqualsTableByKeyTests.E VALUES(1,2);
  INSERT AssertEqualsTableByKeyTests.A VALUES(1,3);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertEqualsTableByKey ''[AssertEqualsTableByKeyTests].[E]'',''AssertEqualsTableByKeyTests.A'',''Id'';',
    '%Changed%V%2%3%';
  CREATE TABLE #Expected(Id INT,V INT);
  INSERT #Expected VALUES(1,2);
  EXEC tSQLt.AssertEqualsTable '#Expected','AssertEqualsTableByKeyTests.E';
  UPDATE #Expected SET V=3;
  EXEC tSQLt.AssertEqualsTable '#Expected','AssertEqualsTableByKeyTests.A';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test absent expected table fails clearly]
AS
BEGIN
  CREATE TABLE #A(Id INT);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertEqualsTableByKey ''#NoSuchExpectedTable'',''#A'',''Id'';',
    '%#NoSuchExpectedTable%does not exist%';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test absent actual table fails clearly]
AS
BEGIN
  CREATE TABLE #E(Id INT);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#NoSuchActualTable'',''Id'';',
    '%#NoSuchActualTable%does not exist%';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test duplicate keys are detected after common type conversion]
AS
BEGIN
  CREATE TABLE #E(Id INT,V INT);
  CREATE TABLE #A(Id VARCHAR(10),V INT);
  INSERT #E VALUES(1,1);
  INSERT #A VALUES('01',1),('1',2);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%duplicate keys in #A%DuplicateCount%1%2%';
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test long duplicate key output is cut at a row boundary with a note]
AS
BEGIN
  CREATE TABLE #E(Id INT,V INT);
  CREATE TABLE #A(Id INT,V INT);
  INSERT #E VALUES(1,1);
  INSERT #A SELECT N.Id,V.V
    FROM (SELECT TOP(300) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) Id FROM sys.columns) N
   CROSS JOIN (SELECT 1 V UNION ALL SELECT 2) V;
  DECLARE @Error NVARCHAR(MAX);
  BEGIN TRY
    EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
  END TRY
  BEGIN CATCH
    SET @Error=ERROR_MESSAGE();
  END CATCH;
  DECLARE @Pattern NVARCHAR(MAX) = N'%duplicate keys in #A%|'+CHAR(13)+CHAR(10)+N'... (output truncated; 300 duplicate keys in total)';
  EXEC tSQLt.AssertLike @Pattern,@Error;
  DECLARE @Length INT = DATALENGTH(@Error)/2;
  IF @Length > 2047 EXEC tSQLt.Fail 'Expected the duplicate key error to fit in 2047 characters, but it has ',@Length;
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test system errors keep their original error number in the message]
AS
BEGIN
  CREATE TABLE #E(Id INT,V INT);
  CREATE TABLE #A(Id INT,V VARCHAR(10));
  INSERT #E VALUES(1,1);
  INSERT #A VALUES(1,'abc');
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='Msg 245: %',@ExpectedSeverity=16;
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test compatible types compare without narrowing actual values]
AS
BEGIN
  CREATE TABLE #E(Id INT,V VARCHAR(1));
  CREATE TABLE #A(Id BIGINT,V VARCHAR(20));
  INSERT #E VALUES(1,'a');
  INSERT #A VALUES(1,'ab');
  EXEC tSQLt_testutil.AssertFailMessageLike 'EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''Id'';',
    '%Changed%V%a%ab%';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test changed values are formatted by the common type]
AS
BEGIN
  CREATE TABLE #E(Id INT,V INT);
  CREATE TABLE #A(Id INT,V FLOAT);
  INSERT #E VALUES(1,1);
  INSERT #A VALUES(1,1.0000001);
  EXEC tSQLt_testutil.AssertFailMessageLike 'EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''Id'';',
    '%Changed%V%1.000000000000000e+000%1.000000100000000e+000%';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test unquoted key list accepts whitespace characters]
AS
BEGIN
  CREATE TABLE #E(Id INT,Line INT);
  CREATE TABLE #A(Id INT,Line INT);
  DECLARE @Keys NVARCHAR(MAX);
  SET @Keys=NCHAR(9)+N'Id'+NCHAR(9)+N','+NCHAR(10)+N'Line'+NCHAR(13);
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A',@Keys;
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test duplicate count diagnostic handles a key named DuplicateCount]
AS
BEGIN
  CREATE TABLE #E(DuplicateCount INT);
  CREATE TABLE #A(DuplicateCount INT);
  INSERT #E VALUES(7),(7);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%duplicate keys in #E%Key1: DuplicateCount%DuplicateCount%7%2%';
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','DuplicateCount';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test null to value and value to null both produce changes]
AS
BEGIN
  CREATE TABLE #E(Id INT,V NVARCHAR(20));
  CREATE TABLE #A(Id INT,V NVARCHAR(20));
  INSERT #E VALUES(1,NULL),(2,N'value');
  INSERT #A VALUES(1,N'value'),(2,NULL);
  EXEC tSQLt_testutil.AssertFailMessageLike 'EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''Id'';',
    '%Changed%V%!NULL!%value%Changed%V%value%!NULL!%';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[Assert supported type]
  @Type NVARCHAR(MAX),@Value NVARCHAR(MAX)
AS
BEGIN
  DECLARE @Cmd NVARCHAR(MAX);
  SET @Cmd=N'CREATE TABLE #E(Id INT,V '+@Type+N'); CREATE TABLE #A(Id INT,V '+@Type+N');
    INSERT #E VALUES(1,'+@Value+N'); INSERT #A SELECT * FROM #E;
    EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''Id'';
    UPDATE #A SET V=NULL;
    EXEC tSQLt_testutil.AssertFailMessageLike ''EXEC tSQLt.AssertEqualsTableByKey ''''#E'''',''''#A'''',''''Id'''';'',''%Changed%V%'';';
  -- Database-scoped CLR types cannot be used in tempdb temporary tables.
  IF @Type LIKE 'tSQLt_testutil.%'
    SET @Cmd=REPLACE(REPLACE(@Cmd,'#E','AssertEqualsTableByKeyTests.TypeExpected'),'#A','AssertEqualsTableByKeyTests.TypeActual')+
      N' DROP TABLE AssertEqualsTableByKeyTests.TypeExpected; DROP TABLE AssertEqualsTableByKeyTests.TypeActual;';
  EXEC(@Cmd);
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test supported types compare and render changes]
AS
BEGIN
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'BIT','1';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'TINYINT','1';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'SMALLINT','1';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'INT','1';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'BIGINT','1';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'DECIMAL(20,8)','1.12345678';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'NUMERIC(20,8)','1.12345678';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'MONEY','1.12';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'SMALLMONEY','1.12';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'FLOAT','1E-12';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'REAL','1E-12';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'CHAR(10)','''text''';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'NCHAR(10)','N''日本語''';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'VARCHAR(MAX)','''text''';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'NVARCHAR(MAX)','N''日本語''';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'BINARY(4)','0x12345678';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'VARBINARY(MAX)','0x12345678';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'DATETIME','''20200101''';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'SMALLDATETIME','''20200101''';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'UNIQUEIDENTIFIER','''12345678-1234-1234-1234-123456789ABC''';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'SQL_VARIANT','CAST(123 AS INT)';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test post 2005 types compare and render changes]
AS
BEGIN
  IF CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)),4) AS INT)<10 RETURN;
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'DATE','''20200101''';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'TIME','''12:34:56.1234567''';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'DATETIME2','''2020-01-01T12:34:56.1234567''';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'DATETIMEOFFSET','''2020-01-01T12:34:56.1234567+09:00''';
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'HIERARCHYID','''/1/''';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[Assert unsupported type]
  @Type NVARCHAR(MAX)
AS
BEGIN
  DECLARE @Error NVARCHAR(MAX),@Cmd NVARCHAR(MAX);
  SET @Cmd=N'CREATE TABLE #E(Id INT,V '+@Type+N'); CREATE TABLE #A(Id INT,V '+@Type+N');
    EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''Id'';';
  IF @Type LIKE 'tSQLt_testutil.%'
    SET @Cmd=REPLACE(REPLACE(@Cmd,'#E','AssertEqualsTableByKeyTests.TypeExpected'),'#A','AssertEqualsTableByKeyTests.TypeActual');
  BEGIN TRY
    EXEC(@Cmd);
  END TRY
  BEGIN CATCH
    SET @Error=ERROR_MESSAGE();
  END CATCH;
  IF OBJECT_ID('AssertEqualsTableByKeyTests.TypeExpected') IS NOT NULL DROP TABLE AssertEqualsTableByKeyTests.TypeExpected;
  IF OBJECT_ID('AssertEqualsTableByKeyTests.TypeActual') IS NOT NULL DROP TABLE AssertEqualsTableByKeyTests.TypeActual;
  EXEC tSQLt.AssertLike '%datatype that is not supported for tSQLt.AssertEqualsTableByKey%',@Error;
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test unsupported type family is rejected]
AS
BEGIN
  EXEC AssertEqualsTableByKeyTests.[Assert unsupported type] 'TEXT';
  EXEC AssertEqualsTableByKeyTests.[Assert unsupported type] 'NTEXT';
  EXEC AssertEqualsTableByKeyTests.[Assert unsupported type] 'IMAGE';
  EXEC AssertEqualsTableByKeyTests.[Assert unsupported type] 'XML';
  EXEC AssertEqualsTableByKeyTests.[Assert unsupported type] 'ROWVERSION';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test monetary differences display all four decimal places]
AS
BEGIN
  CREATE TABLE #E(Id INT,V MONEY);
  CREATE TABLE #A(Id INT,V MONEY);
  INSERT #E VALUES(1,1.1234);
  INSERT #A VALUES(1,1.1235);
  EXEC tSQLt_testutil.AssertFailMessageLike 'EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''Id'';',
    '%Changed%V%1.1234%1.1235%';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test byte ordered CLR types compare and non byte ordered types are rejected]
AS
BEGIN
  EXEC AssertEqualsTableByKeyTests.[Assert supported type] 'tSQLt_testutil.DataTypeByteOrdered','''10''';
  EXEC AssertEqualsTableByKeyTests.[Assert unsupported type] 'tSQLt_testutil.DataTypeNoEqual';
  EXEC AssertEqualsTableByKeyTests.[Assert unsupported type] 'tSQLt_testutil.DataTypeWithEqual';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test CLR keys can be rendered in changed and duplicate diagnostics]
AS
BEGIN
  CREATE TABLE AssertEqualsTableByKeyTests.ClrE(Id tSQLt_testutil.DataTypeByteOrdered,V INT);
  CREATE TABLE AssertEqualsTableByKeyTests.ClrA(Id tSQLt_testutil.DataTypeByteOrdered,V INT);
  INSERT AssertEqualsTableByKeyTests.ClrE VALUES('10',1);
  INSERT AssertEqualsTableByKeyTests.ClrA VALUES('10',2);
  EXEC tSQLt_testutil.AssertFailMessageLike
    'EXEC tSQLt.AssertEqualsTableByKey ''AssertEqualsTableByKeyTests.ClrE'',''AssertEqualsTableByKeyTests.ClrA'',''Id'';',
    '%10%Changed%V%1%2%';
  INSERT AssertEqualsTableByKeyTests.ClrA VALUES('10',3);
  EXEC tSQLt.ExpectException @ExpectedMessagePattern='%duplicate keys in AssertEqualsTableByKeyTests.ClrA%10%2%';
  EXEC tSQLt.AssertEqualsTableByKey 'AssertEqualsTableByKeyTests.ClrE','AssertEqualsTableByKeyTests.ClrA','Id';
END;
GO
CREATE PROCEDURE AssertEqualsTableByKeyTests.[test working tables are removed on success and failure]
AS
BEGIN
  CREATE TABLE #E(Id INT,V INT);
  CREATE TABLE #A(Id INT,V INT);
  INSERT #E VALUES(1,2);
  INSERT #A VALUES(1,2);
  EXEC tSQLt.SpyProcedure 'tSQLt.Fail','RAISERROR(''Expected assertion failure'',16,10);';
  DECLARE @Before INT,@After INT,@Error NVARCHAR(MAX);
  SELECT @Before=COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID('tSQLt');
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
  SELECT @After=COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID('tSQLt');
  EXEC tSQLt.AssertEquals @Before,@After;
  UPDATE #A SET V=3;
  BEGIN TRY
    EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
  END TRY
  BEGIN CATCH
    SET @Error=ERROR_MESSAGE();
  END CATCH;
  EXEC tSQLt.AssertEqualsString 'Expected assertion failure',@Error;
  SELECT @After=COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID('tSQLt');
  EXEC tSQLt.AssertEquals @Before,@After;
  SET @Error=NULL;
  BEGIN TRY
    EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id,';
  END TRY
  BEGIN CATCH
    SET @Error=ERROR_MESSAGE();
  END CATCH;
  EXEC tSQLt.AssertLike '%@KeyColumns must be a nonempty list%',@Error;
  SELECT @After=COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID('tSQLt');
  EXEC tSQLt.AssertEquals @Before,@After;
END;
GO
