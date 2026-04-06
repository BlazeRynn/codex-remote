@echo off
setlocal
pushd "%~dp0"
dart run bin\codex_proxy.dart %*
set CODE=%ERRORLEVEL%
popd
exit /b %CODE%
