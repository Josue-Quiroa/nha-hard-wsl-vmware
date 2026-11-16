@echo off
REM map-drives-2018.bat - logon script antiguo (sustituido por GPP). LAB: FICTICIO
net use S: \\NYX-SQL01\Reports /user:NYXCORE\svc_sql_old SqlOld#2016 /persistent:no
net use B: \\NYX-BKP01\Repo /user:NYXCORE\adm.backup Backup2018! /persistent:no
