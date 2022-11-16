@echo off

COPY  "scripts\configs\config_1.yml" ".circleci\config.yml"
DEL  ".circleci\continue-config.yml"
