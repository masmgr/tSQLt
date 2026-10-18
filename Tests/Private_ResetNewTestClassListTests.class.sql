EXEC tSQLt.NewTestClass 'Private_ResetNewTestClassListTests';
GO
CREATE PROCEDURE Private_ResetNewTestClassListTests.[test records all current test classes replacing the previous list]
AS
BEGIN
  EXEC tSQLt.FakeTable @TableName = 'tSQLt.Private_PreviousTestClassList';
  EXEC tSQLt.FakeTable @TableName = 'tSQLt.TestClasses';
  INSERT INTO tSQLt.Private_PreviousTestClassList VALUES('old class');
  EXEC ('INSERT INTO tSQLt.TestClasses(Name) VALUES(''tc1''),(''tc2''),(''tc2'');');

  EXEC tSQLt.Private_ResetNewTestClassList;

  SELECT TOP(0) ClassName INTO #Expected FROM tSQLt.Private_PreviousTestClassList;
  INSERT INTO #Expected VALUES('tc1'),('tc2');
  EXEC tSQLt.AssertEqualsTable '#Expected','tSQLt.Private_PreviousTestClassList';
END;
GO
CREATE PROCEDURE Private_ResetNewTestClassListTests.[test clears the previous list when no test classes remain]
AS
BEGIN
  EXEC tSQLt.FakeTable @TableName = 'tSQLt.Private_PreviousTestClassList';
  EXEC tSQLt.FakeTable @TableName = 'tSQLt.TestClasses';
  INSERT INTO tSQLt.Private_PreviousTestClassList VALUES('old class');

  EXEC tSQLt.Private_ResetNewTestClassList;

  EXEC tSQLt.AssertEmptyTable 'tSQLt.Private_PreviousTestClassList';
END;
GO
