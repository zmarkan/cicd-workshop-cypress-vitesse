@echo off

COPY  "scripts\configs\config_2.yml" ".circleci\config.yml"
DEL  ".circleci\continue-config.yml"
