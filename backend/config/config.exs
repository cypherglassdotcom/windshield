# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Configures the endpoint
config :windshield, WindshieldWeb.Endpoint,
  # this is your external or intranet public address, elixir will allow
  # requests coming only from this address, i.e.:
  # [host: "http://windshield.domain.com", port: 80] # or https, port 443
  url: [host: "http://localhost", port: 3000],

  # feel free to regenerate your secret key base
  secret_key_base: "r+MB0ulg6JuSMjyynzC62i3Dba6R1+HJ1MhMG8YUGzJWwxOwU5faCWjkOoaLB9Qq",
  render_errors: [view: WindshieldWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: Windshield.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configures the SLACK ALERT HOOK
config :windshield, :slack_alert,
  hook: "https://hooks.slack.com/services/xxxx/yyyy/zzzz",
  channel: "#general",
  username: "Cypherglass WINDSHIELD",
  icon: ":warning:"

# Configures the SMTP for EMAIL ALERTS
config :windshield, Windshield.Mailer,
       adapter: Bamboo.SMTPAdapter,
       server: "localhost",
       port: 25,
       username: "",
       password: "",
       sender_email: "outbound@awesome.com",
       tls: :always, # can be `:always` or `:never`
       ssl: false, # can be `true`
       retries: 3,
       recipients: [ "it_guy@awesome.com", "cursed_developer@awesome.com" ]

# !!! IMPORTANT !!! This is the password used to unlock WINDSHIELD Interface
# and be able to add nodes and edit settings, please change it!
config :windshield, Windshield.SystemAuth,
  salt: "d06d863b06fc758cbe549b832b025bc25e694013",
  password: "zxc123",
  user: "sadmin"

# SETUP MONGODB
config :mongodb, Mongo,
  database: "windshield_aye_dawn24",
  name: :windshield,
  pool: DBConnection.Poolboy

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
