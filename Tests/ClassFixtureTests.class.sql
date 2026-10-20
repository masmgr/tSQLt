EXEC tSQLt.NewTestClass N'ClassFixtureTests';
GO
CREATE PROCEDURE ClassFixtureTests.SetUp
AS
BEGIN
  EXEC tSQLt.NewTestClass N'FixtureRegistration';
  EXEC(N'CREATE PROCEDURE FixtureRegistration.Prepare AS RETURN;');
  EXEC(N'CREATE PROCEDURE FixtureRegistration.OtherPrepare AS RETURN;');
END;
GO
CREATE PROCEDURE ClassFixtureTests.[test registration replaces and unregisters]
AS
BEGIN
  EXEC tSQLt.RegisterClassFixture N'FixtureRegistration',N'FixtureRegistration.Prepare';
  EXEC tSQLt.RegisterClassFixture N'FixtureRegistration',N'FixtureRegistration.OtherPrepare';
  DECLARE @Count INT=(SELECT COUNT(*) FROM tSQLt.Private_ClassFixture WHERE ClassId=SCHEMA_ID(N'FixtureRegistration')),
    @Id INT=(SELECT SetUpObjectId FROM tSQLt.Private_ClassFixture WHERE ClassId=SCHEMA_ID(N'FixtureRegistration')),
    @Expected INT=OBJECT_ID(N'FixtureRegistration.OtherPrepare');
  EXEC tSQLt.AssertEquals 1,@Count;
  EXEC tSQLt.AssertEquals @Expected,@Id;
  EXEC tSQLt.RegisterClassFixture N'FixtureRegistration',NULL;
  IF EXISTS(SELECT 1 FROM tSQLt.Private_ClassFixture WHERE ClassId=SCHEMA_ID(N'FixtureRegistration'))
    EXEC tSQLt.Fail N'Registration was not removed.';
END;
GO
CREATE PROCEDURE ClassFixtureTests.[test setup from another class is rejected]
AS
BEGIN
  EXEC tSQLt.ExpectException @ExpectedMessagePattern=N'ClassSetUp must be%';
  EXEC tSQLt.RegisterClassFixture N'FixtureRegistration',N'ClassFixtureTests.SetUp';
END;
GO
CREATE PROCEDURE ClassFixtureTests.[test parameterized setup is rejected]
AS
BEGIN
  EXEC(N'CREATE PROCEDURE FixtureRegistration.WithParameter @Id INT=1 AS RETURN;');
  EXEC tSQLt.ExpectException @ExpectedMessagePattern=N'ClassSetUp must be%';
  EXEC tSQLt.RegisterClassFixture N'FixtureRegistration',N'FixtureRegistration.WithParameter';
END;
GO
CREATE PROCEDURE ClassFixtureTests.[test DropClass removes registration]
AS
BEGIN
  EXEC tSQLt.RegisterClassFixture N'FixtureRegistration',N'FixtureRegistration.Prepare';
  DECLARE @Id INT=SCHEMA_ID(N'FixtureRegistration');
  EXEC tSQLt.DropClass N'FixtureRegistration';
  IF EXISTS(SELECT 1 FROM tSQLt.Private_ClassFixture WHERE ClassId=@Id)
    EXEC tSQLt.Fail N'DropClass left a registration.';
END;
GO
