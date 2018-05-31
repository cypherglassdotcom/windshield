#!/bin/sh

cd frontend
# npm install

cd ../backend
mix deps.get

npm start --prefix ../frontend &
npm run watch-css --prefix ../frontend &
mix phx.server

wait
echo all processes complete
