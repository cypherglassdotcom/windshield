#!/bin/bash

elm-app build
sudo rm -rf /var/www/html
sudo cp -R build /var/www/html
