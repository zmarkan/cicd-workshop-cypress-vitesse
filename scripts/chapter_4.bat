@echo off

COPY  "scripts\configs\config_4.yml" ".circleci\config.yml"
DEL  ".circleci\continue-config.yml"
