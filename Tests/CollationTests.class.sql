EXEC tSQLt.NewTestClass N'CollationTests';
GO
CREATE PROCEDURE CollationTests.[test fake table preserves data collation and quoted names]
AS
BEGIN
  CREATE TABLE CollationTests.[日本'語]]表](Id INT, [名]]前] NVARCHAR(50) COLLATE Latin1_General_CS_AS DEFAULT N'初期');
  EXEC tSQLt.FakeTable N'CollationTests.[日本''語]]表]', @Defaults=1;
  DECLARE @Collation NVARCHAR(128);
  SELECT @Collation=collation_name FROM sys.columns
    WHERE object_id=OBJECT_ID(N'CollationTests.[日本''語]]表]') AND column_id=2;
  EXEC tSQLt.AssertEqualsString N'Latin1_General_CS_AS',@Collation;
  INSERT CollationTests.[日本'語]]表](Id) VALUES(1);
  CREATE TABLE #Expected(Id INT, [名]]前] NVARCHAR(50) COLLATE Latin1_General_CS_AS);
  INSERT #Expected VALUES(1,N'初期');
  EXEC tSQLt.AssertEqualsTable N'#Expected',N'CollationTests.[日本''語]]表]';
  EXEC tSQLt.AssertEqualsTableByKey N'#Expected',N'CollationTests.[日本''語]]表]',N'Id';
END;
GO
CREATE PROCEDURE CollationTests.[test apply primary foreign and check constraints]
AS
BEGIN
  CREATE TABLE CollationTests.Parent(Id INT CONSTRAINT PK_Parent PRIMARY KEY);
  CREATE TABLE CollationTests.Child(Id INT, ParentId INT,
    CONSTRAINT FK_Child FOREIGN KEY(ParentId) REFERENCES CollationTests.Parent(Id),
    CONSTRAINT CK_Child CHECK(Id>0));
  EXEC tSQLt.FakeTable N'CollationTests.Parent';
  EXEC tSQLt.FakeTable N'CollationTests.Child';
  EXEC tSQLt.ApplyConstraint N'CollationTests.Parent',N'PK_Parent';
  EXEC tSQLt.ApplyConstraint N'CollationTests.Child',N'FK_Child';
  EXEC tSQLt.ApplyConstraint N'CollationTests.Child',N'CK_Child';
  INSERT CollationTests.Parent VALUES(1);
  INSERT CollationTests.Child VALUES(1,1);
END;
GO
CREATE PROCEDURE CollationTests.[test ordinary comparison retains SQL string semantics]
AS
BEGIN
  CREATE TABLE #E(Id INT, Val NVARCHAR(50) COLLATE Japanese_CI_AS);
  CREATE TABLE #A(Id INT, Val NVARCHAR(50) COLLATE Japanese_CI_AS);
  INSERT #E VALUES(1,N'abc');
  INSERT #A VALUES(1,N'ABC ');
  EXEC tSQLt.AssertEqualsTable '#E','#A';
  EXEC tSQLt.AssertEqualsTableByKey '#E','#A','Id';
END;
GO
CREATE PROCEDURE CollationTests.[test fake function and spy generate parameter definitions]
AS
BEGIN
  EXEC(N'CREATE FUNCTION CollationTests.[関数]]元](@値 NVARCHAR(10)) RETURNS NVARCHAR(10) AS BEGIN RETURN @値; END;');
  EXEC(N'CREATE FUNCTION CollationTests.[関数]]偽](@値 NVARCHAR(10)) RETURNS NVARCHAR(10) AS BEGIN RETURN N''偽''; END;');
  EXEC tSQLt.FakeFunction N'CollationTests.[関数]]元]',N'CollationTests.[関数]]偽]';
  EXEC(N'DECLARE @Actual NVARCHAR(10)=CollationTests.[関数]]元](N''元''); EXEC tSQLt.AssertEqualsString N''偽'',@Actual;');
  EXEC(N'CREATE PROCEDURE CollationTests.[手続]]元] @値 NVARCHAR(10) AS RETURN;');
  EXEC tSQLt.SpyProcedure N'CollationTests.[手続]]元]';
  EXEC(N'EXEC CollationTests.[手続]]元] @値=N''入力'';');
  EXEC tSQLt.AssertProcedureCalled N'CollationTests.[手続]]元]';
END;
GO
