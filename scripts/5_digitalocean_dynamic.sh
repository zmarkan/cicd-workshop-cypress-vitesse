#!/usr/bin/shell

rm -f .circleci/continue_config.yml

# cp scripts/do/README.md .
cp -f scripts/do/configs/config_5_setup.yml ./circleci/config.yml
cp -f scripts/do/configs/config_5_continue.yml ./circleci/continue_config.yml


