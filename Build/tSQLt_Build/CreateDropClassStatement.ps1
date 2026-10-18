using module "../CommonFunctionsAndMethods.psm1";
Push-Location -Path $PSScriptRoot;
try{
  $baseDir = '..';
  $buildPath = $baseDir +'/';
  $tempPath = $baseDir + '/temp/tSQLtBuild/';
  $sourcePath = $baseDir + '/../Source/';

  Log-Output '<!--========          Start CreateDropClassStatement.ps1          =========-->'

  $DropClassFileContent = Get-Content -path ($sourcePath+"tSQLt.DropClass.ssp.sql");
  $GetDropItemCmdFileContent = Get-Content -path ($sourcePath+"tSQLt.Private_GetDropItemCmd.sfn.sql");
  $TemplateFileContent = Get-Content -path ($sourcePath+"tSQLt.TempDropStatement.mdl.sql");

  $OutputFilePath = $tempPath+"TempDropClass.sql";

  $DropClassSnip = ($DropClassFileContent | Get-SnipContent -startSnipPattern "/*SnipStart: CreateDropClassStatement.ps1*/" -endSnipPattern "/*SnipEnd: CreateDropClassStatement.ps1*/");
  $DropItemSnip = ($GetDropItemCmdFileContent | Get-SnipContent -startSnipPattern "/*SnipStart: CreateDropClassStatement.ps1*/" -endSnipPattern "/*SnipEnd: CreateDropClassStatement.ps1*/");
  $DropItemParamSnip = ($GetDropItemCmdFileContent | Get-SnipContent -startSnipPattern "/*SnipParamStart: CreateDropClassStatement.ps1*/" -endSnipPattern "/*SnipParamEnd: CreateDropClassStatement.ps1*/");

  $VariablesString = ($DropItemParamSnip.trim() -join ' ')

  $VariableNames = (Select-String '@\S+' -input $VariablesString -AllMatches|ForEach-Object{$_.matches.Value});

  $DISP1 =   ($DropItemSnip | ForEach-Object{
      $s=$_;
      for($i = 0;$i -lt $VariableNames.count;$i++){
        $s=$s -replace $VariableNames[$i], ("($"+($i+1)+")") 
      };
      $s; 
  });
  $DISP2 = $DISP1.trim() -join ' ';

  $DropItemSnipPrepared = "("+ $DISP2 + ")";
  $RawDropClassStatement = $DropClassSnip -replace 'tSQLt.Private_GetDropItemCmd\s*\(\s*([^,]*)\s*,\s*([^)]*)\s*\)',$DropItemSnipPrepared;

  $DropClassStatement = ($RawDropClassStatement.trim()|Where-Object {$_ -ne "" -and $_ -notmatch "^GO(\s.*)?"}) -join ' ';
  Log-Output("OutputFilePath:$OutputFilePath")

  Set-Content -Path $OutputFilePath -Value ($TemplateFileContent.Replace("/*--DROPSTATEMENT--*/",$DropClassStatement));

  # Reuse the same dependency-free schema removal for standalone recovery.
  $UninstallTemplate = Get-Content -Raw -Path ($sourcePath+"tSQLt.Uninstall.mdl.sql");
  $UninstallContent = Get-Content -Path ($sourcePath+"tSQLt.Uninstall.ssp.sql");
  $UninstallSnip = ($UninstallContent | Get-SnipContent -startSnipPattern "/*SnipStart: StandaloneUninstall*/" -endSnipPattern "/*SnipEnd: StandaloneUninstall*/") -join [Environment]::NewLine;
  $UninstallScript = $UninstallTemplate.Replace("/*--DROPSTATEMENT--*/",$DropClassStatement).Replace("/*--UNINSTALL--*/",$UninstallSnip);
  Set-Content -Path ($tempPath+"Uninstall.sql") -Value $UninstallScript;

  Log-Output '<!--========            End CreateDropClassStatement.ps1          =========-->'
}
finally{
  Pop-Location;
}  
  
  <# TODO
  --> this makes tSQLt.class.sql truely re-runnable
  --> Test this: Empty File TempDropClass.sql file should throw an error
  --> Test this: If the $tempPath does not exist, BuildHelper.exe seems to currently throw an error, but does that stop the build?
  --> Test this: If the $sourcePath does not exist, BuildHelper.exe seems to currently throw an error, but does that stop the build?
  #>
