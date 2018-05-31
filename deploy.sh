#!/bin/bash

# backend
cd backend
mix deps.get
./start.sh

# frontend
cd ../frontend
elm-app build
sudo rm -rf /var/www/html
sudo cp -R build /var/www/html
