# Cypherglass WINDSHIELD

WINDSHIELD is a tool for Block Producers to monitor their EOS Infrastructure.
It is designed to run from a privileged host inside your intranet and provide data on all nodes, even those that are not exposed to the internet.

## Functionalities

1. Alert when the principal Block Producer node has not created a block in X time.
1. Alert if our node forks or become unsynced.
1. Alert if our node stops responding.
1. Alert if our Full nodes aren't in sync with our BP.
1. Alert when our node moves in the vote list (like if we move from the node with the 5th highest votes to the 6th highest)
1. Alert if 1/3 of BPs are off - in this case BPs need to fix the network.

## WINDSHIELD Structure

```
/backend   # contains the server application, made with elixir + mongodb
/frontend  # contains the UI web application Static HTML, made with elm + js + html
```

## Installation Steps

You need to prepare your server to have the backend elixir process always running. By default it runs on port 4000. And for the UI of the application you need to serve the static HTML files using a webserver like Apache.

Prepare the WINDSHIELD root folder by cloning this repo, we will call it the WINDSHIELD root folder.

`~/windshield`

Now, follow the next steps to fully setup WINDSHIELD.

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

Setup your server sensitive informations on `~/windshield/backend/config/config.exs`, the file is self-explanatory and has instructions. After you setup all the basic info, create the file `~/windshield/backend/config/prod.secret.exs` in your production environment only with sensitive data.

```
use Mix.Config

config :mongodb, Mongo,
  database: "windshield_v1"

config :windshield, Windshield.Mailer,
       server: "localhost",
       port: 25,
       username: "myuser",
       password: "mypass",
       sender_email: "outbound@awesome.com"

config :windshield, WindshieldWeb.Endpoint,
  secret_key_base: "YOUR_SUPER_SECRET_HASH"

config :windshield, :slack_alert,
  hook: "https://hooks.slack.com/services/XXXXXX/YYYYY/ZZZZZZZZZ"

config :windshield, Windshield.SystemAuth,
  salt: "SUPER_SALT",
  password: "mY#sUp3R@p4SsW0rD!",
  user: "sadmin"
```

The above is only an example of the secret file, you can copy and paste and edit with your real values. Usually we do that because developers share the default `config.exs`, it should never have any sensitive production data, then the system admin can deploy all the production secret and sensitive parameters in the `prod.secret.exs` file.

Finally, to start the WINDSHIELD server:

```
cd ~/windshield/backend
mix deps.get
./start.sh
curl http://localhost:4000/api/health-check
```

If the installation was successfull you should see an `"OK"` after the last command.

### Frontend UI Installation

Here we assume that you have `node` & `npm` installed already in your server, there are many ways to install it and we usually recommend the `nvm` one. After you install node (you can check by running `node -v`), follow the next steps to fully deploy the frontend HTML and JS static files.

```
cd ~/windshield/frontend
cp .env.example .env
nano .env                   # SETUP YOUR DOMAIN/IP ADDRESSES
npm install -g elm
npm install -g elm-github-install
npm install -g create-elm-app
npm install
elm-app build
```

From the above steps you will have a `build` folder. This is the folder that you will put in your webserver. Assuming that you have Apache2, you can just put it on the root webserver folder (it must be in a root address to work - you can use `domain.com`, `windshield.domain.com`, so on, but does not work in a regular subpath like `domain.com/windshield`):

```
sudo rm -rf /var/www/html
sudo cp -R build /var/www/html
```

Just open your webserver address and if everything is correct you will receive a green success toast saying: `"Connected to WINDSHIELD Server"`

Config file sample `/etc/apache2/sites-enabled/000-default.conf` for Apache2:

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

### Nodes Setup

Ok, now that you had setup the server it's the fun time! Let's setup your nodes so you can keep track of them and receive any crictical alerts and keep watching their synchronization and performance.

1. Click in the `locker` icon and enter the password you setup on the backend configs.
1. Now click in add node and add your main BlockProducer info. It's important that you put the same name of the EOS block producer account, so we can give you stats of when you are producing or not. WINDSHIELD uses this node as the principal one to monitor blocks production.
1. Now click in add node and add your full nodes info, you can put any account name because it your public nodes does not have an account anyways, just set a unique name for easy identification as `fullnode.us1`.
1. After you setup your block producer node and full nodes, click in `Settings` on the top menu and edit the form with your preferred options and add your Block Producer as the Principal Node account. Usually the default settings are good to start and you don't need to play with it, but you can always adjust later.
1. Click on save, go back to the `Dashboard` page, do a refresh and your nodes will automatically starts to synchronize.

PS: You will receive alerts saying that you need to enter the first top 21 block producer nodes. To do this just add all of the block producers nodes as External Node using their public full node information. WINDSHIELD requires this external nodes setup to detect fork and also the 1/3 Network Kill, as suggested by Dan Larimer, that if we have 7 BPs off we should stop the network, find the problem and restart it.

## Special Thanks

   * All the people who made the Jungle Test Net a success.
   * The people at Cryptolions for their great monitor software which inspired this effort.
   * Bohdan CryptoLions For great patience and lots of help.
