@echo off

COPY  "scripts\configs\config_3.yml" ".circleci\config.yml"
DEL  ".circleci\continue-config.yml"
