 = 'C:\Projects\StonkExchange\db\procedures.sql'
 = Get-Content -Raw -Path 
 =  -replace 'RETURNS ([A-Z]+) AS ', 'RETURNS  AS  '
 =  -replace 'END;\s*LANGUAGE plpgsql;', 'END;\n LANGUAGE plpgsql;'
Set-Content -LiteralPath  -Value 
