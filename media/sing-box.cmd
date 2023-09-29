@ECHO OFF & SET EXE=sing-box.exe
TITLE %EXE% [%1] & COLOR 02 & SETLOCAL EnableExtensions
FOR /F %%x IN ('tasklist /NH /FI "IMAGENAME eq %EXE%"') DO IF NOT %%x == %EXE% (
	IF [%1] == [] ( @%EXE% run ) ELSE ( @%EXE% run -c %1 )
) ELSE ( msg "%username%" %EXE% is Running, Close %EXE% Window! ) 