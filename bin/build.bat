@echo off
cd /d %~dp0\src_exec
clang++ -std=c++17 -O2 glld.cpp -o ..\glld.exe
if errorlevel 1 exit /b %errorlevel%
clang++ -std=c++17 -O2 gstdo.cpp -o ..\gstdo.exe
if errorlevel 1 exit /b %errorlevel%
clang++ -std=c++17 -O2 timer.cpp -o ..\timer.exe
if errorlevel 1 exit /b %errorlevel%
clang++ -std=c++17 -O2 gfree.cpp -o ..\gfree.exe
if errorlevel 1 exit /b %errorlevel%
echo Built Windows executables in %~dp0
