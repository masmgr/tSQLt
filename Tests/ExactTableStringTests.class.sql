EXEC tSQLt.NewTestClass N'ExactTableStringTests';
GO
CREATE PROCEDURE ExactTableStringTests.[test exact differences use full UTF16 values]
AS
BEGIN
  CREATE TABLE #E(Id INT,V NVARCHAR(MAX));
  CREATE TABLE #A(Id INT,V NVARCHAR(MAX));
  INSERT #E VALUES(1,N'abc'),(2,N''),(3,N'a'+NCHAR(13)+NCHAR(10)),(4,REPLICATE(CONVERT(NVARCHAR(MAX),N'x'),5000)+N'a'),
    (5,N'x'+NCHAR(0)),(6,N'Ａ'),(7,N'é');
  INSERT #A VALUES(1,N'ABC '),(2,NULL),(3,N'a'+NCHAR(10)),(4,REPLICATE(CONVERT(NVARCHAR(MAX),N'x'),5000)+N'b'),
    (5,N'x'),(6,N'A'),(7,N'e'+NCHAR(769));
  DECLARE @Msg NVARCHAR(MAX);
  EXEC tSQLt_testutil.CaptureFailMessage
    N'EXEC tSQLt.AssertEqualsTableByKey ''#E'',''#A'',''Id'',@ExactStringColumns=N''V'';',@Msg OUTPUT;
  EXEC tSQLt.AssertLike N'%first difference: 5001%',@Msg;
  EXEC tSQLt.AssertLike N'%\u0000%',@Msg;
  EXEC tSQLt.AssertLike N'%\r\n%',@Msg;
END;
GO
CREATE PROCEDURE ExactTableStringTests.[test null pairs and mixed varchar nvarchar convert before union]
AS
BEGIN
  CREATE TABLE #E(Id INT,V VARCHAR(MAX) COLLATE Latin1_General_CS_AS);
  CREATE TABLE #A(Id INT,V NVARCHAR(MAX) COLLATE Japanese_CI_AS);
  INSERT #E VALUES(1,NULL),(2,'abc ');
  INSERT #A VALUES(1,NULL),(2,N'abc ');
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id',@ExactStringColumns='V';
END;
GO
CREATE PROCEDURE ExactTableStringTests.[test quoted column names and unchanged key semantics]
AS
BEGIN
  CREATE TABLE #E(Id NVARCHAR(10) COLLATE Japanese_CI_AS,[a,b]]] NVARCHAR(20),Other NVARCHAR(20) COLLATE Japanese_CI_AS);
  CREATE TABLE #A(Id NVARCHAR(10) COLLATE Japanese_CI_AS,[a,b]]] NVARCHAR(20),Other NVARCHAR(20) COLLATE Japanese_CI_AS);
  INSERT #E VALUES(N'key',N'same',N'abc');
  INSERT #A VALUES(N'KEY ',N'same',N'ABC ');
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id',@ExactStringColumns=N'[a,b]]]';
END;
GO
CREATE PROCEDURE ExactTableStringTests.[test key column exact specification is rejected]
AS
BEGIN
  CREATE TABLE #E(Id NVARCHAR(10));
  CREATE TABLE #A(Id NVARCHAR(10));
  EXEC tSQLt.ExpectException @ExpectedMessagePattern=N'%@ExactStringColumns must list%';
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id',@ExactStringColumns=N'Id';
END;
GO
CREATE PROCEDURE ExactTableStringTests.[test invalid exact column lists are rejected]
AS
BEGIN
  CREATE TABLE #E(Id INT,V NVARCHAR(10),N INT);
  CREATE TABLE #A(Id INT,V NVARCHAR(10),N INT);
  DECLARE @Lists TABLE(List NVARCHAR(100));
  INSERT @Lists VALUES(N''),(N'V,V'),(N'NoColumn'),(N'N'),(N'V,'),(N'[V');
  DECLARE @List NVARCHAR(100),@Caught BIT;
  DECLARE C CURSOR LOCAL FAST_FORWARD FOR SELECT List FROM @Lists;
  OPEN C; FETCH NEXT FROM C INTO @List;
  WHILE @@FETCH_STATUS=0
  BEGIN
    SET @Caught=0;
    BEGIN TRY
      EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id',@ExactStringColumns=@List;
    END TRY
    BEGIN CATCH
      IF ERROR_MESSAGE() LIKE N'%@ExactStringColumns must list%' SET @Caught=1;
      ELSE EXEC tSQLt.Fail N'Unexpected error validating exact columns.';
    END CATCH;
    IF @Caught=0 EXEC tSQLt.Fail N'Invalid exact column list accepted.',@List;
    FETCH NEXT FROM C INTO @List;
  END;
  CLOSE C; DEALLOCATE C;
END;
GO
