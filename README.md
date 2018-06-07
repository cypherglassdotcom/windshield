# Cypherglass WINDSHIELD

![Cypherglass WINDSHIELD](https://github.com/cypherglassdotcom/windshield/raw/master/banner.png "Cypherglass WINDSHIELD")

WINDSHIELD is A dashboard tool for monitoring internal Block Producer infrastructure.  This tool was designed to run inside a Block Producer’s firewall.  With access to all the BP’s internal nodes, it will alert the BP to issues with their nodes that might not otherwise be apparent.


## List of Alerting Functionality

* Block creation
    - Receive alerts if your Block Producer node has not produced blocks in a specified period of time..
* Forked/unsynchronized node
    - Windshield will let you know if your node has become forked or unsynchronized.
* Handshake response
    - Windshield constantly checks to insure that your node is up and running.
* Full Node to Block Producer node synchronization
    - If your Full Nodes aren’t talking to your Block Producer node Windshield will send you an alert.
* BP vote movement
    - When your node shifts up or down in position among Block Producers Windshield will tell you.
* Availability of one third of block producers
    - If the number of Block Producers available drops below fourteen, Windshield will send you an alert.


## Alerting Formats

* Web based executive dashboard
* Email
* SMS
* Slack

## Type of Nodes

* Block Producer
* Full Node
* External Node

##  Installation

Please feel free to follow the next steps of this document to download and install the latest version of Windshield.

## WINDSHIELD Structure

```
/backend   # contains the server application, made with elixir + mongodb
/frontend  # contains the UI web application Static HTML, made with elm + js + html
```

## Installation Steps

You need to prepare your server to have the backend elixir process always running. By default it runs on port 4000. And for the UI of the application you need to serve the static HTML files using a webserver like Apache.

Prepare the WINDSHIELD root folder by cloning this repo, we will call it the WINDSHIELD root folder.

```
cd ~
git clone https://github.com/cypherglassdotcom/windshield.git
cd ~/windshield
```

Now, follow the next steps to fully setup WINDSHIELD. Usually you will want to create a `windshield` user on your server to go over the next steps and installation instructions.

### Backend Installation

First of all, install elixir on the server:

```
cd ~
wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb
sudo dpkg -i erlang-solutions_1.0_all.deb
sudo apt-get update
sudo apt-get install esl-erlang
sudo apt-get install elixir
```

Then we need to add mongodb, to save and restore chain state:

```
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv EA312927
echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.2.list
sudo apt-get update
sudo apt-get install -y mongodb-org
sudo systemctl start mongod
sudo systemctl enable mongod
```

Now create the file `~/windshield/backend/config/prod.secret.exs` with your server specific data, like the below one:

```
use Mix.Config

# here you setup any secret key hash and your public address + port for windshield
config :windshield, WindshieldWeb.Endpoint,
  secret_key_base: "SUPER_SECRET_KEY_BASE_HASH",
  url: [host: "http://windshield.awesome.com", port: 80]

# here you can setup a slack alert with your slack hook check
# https://api.slack.com/custom-integrations/incoming-webhooks
config :windshield, :slack_alert,
  hook: "https://hooks.slack.com/services/TZZ2KBQ7R/CBRFUSSNR/p5TV1Ow5VVHuMwp9Ue7jWzxv",
  channel: "#general"

# this is the interface master password to setup the monitor nodes and settings
# you can create your secret salt used to token generation
config :windshield, Windshield.SystemAuth,
  salt: "your_secret_salt",
  password: "admin",
  user: "admin"

# setup your smtp settings
config :windshield, Windshield.Mailer,
       server: "localhost",
       port: 25,
       username: "",
       password: "",
       sender_email: "outbound@awesome.com",
       recipients: [ "itguy@awesome.com", "superdev@awesome.com",
       "1234567890@txt.att.net" ] # yes you can also send sms alerts!
```

The above file represents some of the parameters that can be changed. Copy, paste and edit with your specific values.
Other basic settings can be changed in the config files under `~/windshield/backend/config` directory.

Finally, to start the WINDSHIELD server:

```
cd ~/windshield/backend
mix local.hex --force
mix local.rebar
mix deps.get
MIX_ENV=prod mix compile
./start.sh

# after a few seconds (10s) try:
curl http://localhost:4000/api/health-check
```

If the installation was successfull you should see an `"OK"` after the last command. If you don't please open stderr.txt (in this very same directory) and open an issue with the occurred error.

### Frontend UI Installation from Release

You can simply download our latest `frontend-build.zip` release from the [Releases Page](https://github.com/cypherglassdotcom/windshield/releases), unzip it on your webserver root folder (for Apache2 it's usually `/var/www/html`) and change the following line inside `index.html` with your server address:

```
APP_BACKEND_SERVER="http://localhost:4000",APP_SOCKET_SERVER="ws://localhost:4000/socket/websocket"
```

### Frontend UI Compilation (skip if you downloaded the above release)

If you want to compile the frontend, we will assume that you have `node` & `npm` installed already in your server, there are many ways to install it and we usually recommend the `nvm` one (check https://www.digitalocean.com/community/tutorials/how-to-install-node-js-on-ubuntu-16-04#how-to-install-using-nvm).

After node installation is done (you can check by running `node -v`), follow the next steps to fully deploy the frontend HTML and JS static files.

```
cd ~/windshield/frontend
nano public/index.html       # set the APP_BACKEND_SERVER and APP_SOCKET_SERVER
npm install -g elm elm-github-install create-elm-app
npm install
elm-app build
```

### Frontend UI Deploy

From the prior steps you will have a `build` folder or the zipped release. This is the folder that you will put in your webserver.

Assuming that you have Apache2, you can just put it on the root webserver folder (it must be in a root address to work - you can use `domain.com`, `windshield.domain.com`, so on, but does not work in a regular subpath like `domain.com/windshield`):

```
# for release zipped build version
sudo rm -rf /var/www/html
sudo mkdir /var/www/html
sudo cp frontend-build.zip /var/www/html/frontend-build.zip
cd /var/www/html && sudo unzip frontend-build.zip

# for compiled build version
sudo rm -rf /var/www/html
sudo cp -R build /var/www/html
```

Just open your webserver address and if everything is correct you will receive a green success toast saying: `"Connected to WINDSHIELD Server"` - If you don't see this message you should setup your webserver properly to serve the backend endpoints.

Here's a config file sample `/etc/apache2/sites-enabled/000-default.conf` for Apache2:

```
<VirtualHost *:80>
        #ServerName www.example.com  # here you will use the host you setup on config.exs of the backend

        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/html

        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined

        RewriteEngine On
        RewriteCond %{HTTP:Connection} Upgrade [NC]
        RewriteCond %{HTTP:Upgrade} websocket [NC]
        RewriteRule /ws/(.*) ws://localhost:4000/$1 [P,L]

        ProxyPass /api http://localhost:4000/
        ProxyPassReverse /api http://localhost:4000/
</VirtualHost>
```

For the above Apache2 configuration you will need to install the following Apache modules:

```
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod proxy_wstunnel
sudo a2enmod rewrite
sudo service apache2 restart
```

This Apache configuration sets up a proxy that, if your server domain is www.example.com, everything that goes to www.example.com/api will hit the backend http://localhost:4000 and the websockets connecteds to www.example.com/ws will hit the websocket channel at ws://localhost:4000, therefore you should adjust your index.html to your domain:

```
APP_BACKEND_SERVER="http://www.example.com/api",APP_SOCKET_SERVER="ws://www.example.com/ws/socket/websocket"
```

### Nodes Setup

Ok, now that you had setup the server it's the fun time! Let's setup your nodes so you can keep track of them and receive any crictical alerts and keep watching their synchronization and performance.

1. Click in the `locker` icon and enter the password you setup on the `prod.secret.exs` file, it's the master password.
1. Now click in add node and add your main BlockProducer info. It's important that you put the same name of the EOS block producer account, so we can give you stats of when you are producing or not. WINDSHIELD uses this node as the principal one to monitor blocks production.
1. Now click in add node and add your full nodes info, you can put any account name because it your public nodes does not have an account anyways, just set a unique name for easy identification as `fullnode.us1`.
1. After you setup your block producer node and full nodes, click in `Settings` on the top menu and edit the form with your preferred options and add your Block Producer as the Principal Node account. Usually the default settings are good to start and you don't need to play with it, but you can always adjust later.
1. Click on save, go back to the `Dashboard` page, do a refresh and your nodes will automatically starts to synchronize.

PS: You will receive alerts saying that you need to enter the first top 21 block producer nodes. To do this just add all of the block producers nodes as External Node using their public full node information. WINDSHIELD requires this external nodes setup to detect fork and also the 1/3 Network Kill, as suggested by Dan Larimer, that if we have 7 BPs off we should stop the network, find the problem and restart it.

## Special Thanks

   * All the people who made the Jungle Test Net a success.
   * The people at Cryptolions for their great monitor software which inspired this effort.
   * Bohdan CryptoLions For great patience and lots of help.
